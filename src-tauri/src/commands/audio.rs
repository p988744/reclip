//! Audio-related Tauri commands

use reclip_core::{
    audio::AudioProcessor,
    editor::{Editor, EditorConfig},
    exporter::{Exporter, MarkerFormat},
    types::{AnalysisResult, EditReport, Removal, RemovalReason},
    AudioInfo,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tauri::State;

use crate::state::AppState;

/// Frontend removal input
#[derive(Debug, Deserialize)]
pub struct RemovalInput {
    pub start: f64,
    pub end: f64,
    pub reason: String,
    pub text: String,
    pub confidence: f64,
}

/// Frontend analysis input
#[derive(Debug, Deserialize)]
pub struct AnalysisInput {
    pub removals: Vec<RemovalInput>,
    pub original_duration: f64,
    pub removed_duration: f64,
    pub statistics: HashMap<String, u32>,
}

/// Editor configuration input
#[derive(Debug, Deserialize)]
pub struct EditorConfigInput {
    pub crossfade_ms: u32,
    pub min_removal_ms: u32,
    pub merge_gap_ms: u32,
    pub zero_crossing_search_ms: u32,
}

impl Default for EditorConfigInput {
    fn default() -> Self {
        Self {
            crossfade_ms: 30,
            min_removal_ms: 100,
            merge_gap_ms: 50,
            zero_crossing_search_ms: 5,
        }
    }
}

/// Get audio file information
#[tauri::command]
pub fn get_audio_info(path: &str, state: State<AppState>) -> Result<AudioInfo, String> {
    let info = state
        .processor
        .get_info(path)
        .map_err(|e| e.to_string())?;

    *state.current_audio.lock().unwrap() = Some(info.clone());
    Ok(info)
}

/// Edit audio based on analysis
#[tauri::command]
pub fn edit_audio(
    audio_path: &str,
    output_path: &str,
    analysis: AnalysisInput,
    config: Option<EditorConfigInput>,
) -> Result<EditReport, String> {
    let config = config.unwrap_or_default();

    let editor = Editor::new(EditorConfig {
        crossfade_ms: config.crossfade_ms,
        min_removal_ms: config.min_removal_ms,
        merge_gap_ms: config.merge_gap_ms,
        zero_crossing_search_ms: config.zero_crossing_search_ms,
    });

    let removals: Vec<Removal> = analysis
        .removals
        .into_iter()
        .map(|r| Removal {
            start: r.start,
            end: r.end,
            reason: parse_reason(&r.reason),
            text: r.text,
            confidence: r.confidence,
        })
        .collect();

    let analysis_result = AnalysisResult {
        removals,
        original_duration: analysis.original_duration,
        removed_duration: analysis.removed_duration,
        statistics: analysis.statistics,
    };

    editor
        .edit(audio_path, &analysis_result, output_path)
        .map_err(|e| e.to_string())
}

/// Export JSON report
#[tauri::command]
pub fn export_json(report: EditReport, output_path: &str, pretty: bool) -> Result<(), String> {
    Exporter::to_json(&report, output_path, pretty).map_err(|e| e.to_string())
}

/// Export EDL file
#[tauri::command]
pub fn export_edl(
    report: EditReport,
    output_path: &str,
    fps: f64,
    title: Option<String>,
) -> Result<(), String> {
    Exporter::to_edl(&report, output_path, fps, title.as_deref()).map_err(|e| e.to_string())
}

/// Export markers file
#[tauri::command]
pub fn export_markers(report: EditReport, output_path: &str, format: &str) -> Result<(), String> {
    let marker_format = match format {
        "csv" => MarkerFormat::Csv,
        "audacity" | "txt" => MarkerFormat::Audacity,
        _ => MarkerFormat::Csv,
    };

    Exporter::to_markers(&report, output_path, marker_format).map_err(|e| e.to_string())
}

/// Parse removal reason string
fn parse_reason(reason: &str) -> RemovalReason {
    match reason {
        "filler" => RemovalReason::Filler,
        "repeat" => RemovalReason::Repeat,
        "restart" => RemovalReason::Restart,
        "mouth_noise" => RemovalReason::MouthNoise,
        "long_pause" => RemovalReason::LongPause,
        _ => RemovalReason::Filler,
    }
}
