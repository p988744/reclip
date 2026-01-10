//! Reclip Tauri 桌面應用
//!
//! 使用 Tauri 2.0 建立的跨平台桌面應用

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use reclip_core::{
    audio::AudioProcessor,
    editor::{Editor, EditorConfig},
    exporter::{Exporter, MarkerFormat},
    types::{AnalysisResult, EditReport, Removal, RemovalReason},
    AudioInfo,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;
use tauri::State;

/// 應用狀態
struct AppState {
    /// 音訊處理器
    processor: AudioProcessor,
    /// 當前載入的音訊資訊
    current_audio: Mutex<Option<AudioInfo>>,
    /// 當前分析結果
    current_analysis: Mutex<Option<AnalysisResult>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            processor: AudioProcessor::new(48000),
            current_audio: Mutex::new(None),
            current_analysis: Mutex::new(None),
        }
    }
}

/// 前端傳入的移除區間
#[derive(Debug, Deserialize)]
struct RemovalInput {
    start: f64,
    end: f64,
    reason: String,
    text: String,
    confidence: f64,
}

/// 前端傳入的分析結果
#[derive(Debug, Deserialize)]
struct AnalysisInput {
    removals: Vec<RemovalInput>,
    original_duration: f64,
    removed_duration: f64,
    statistics: HashMap<String, u32>,
}

/// 編輯器設定
#[derive(Debug, Deserialize)]
struct EditorConfigInput {
    crossfade_ms: u32,
    min_removal_ms: u32,
    merge_gap_ms: u32,
    zero_crossing_search_ms: u32,
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

/// 取得音訊資訊
#[tauri::command]
fn get_audio_info(path: &str, state: State<AppState>) -> Result<AudioInfo, String> {
    let info = state
        .processor
        .get_info(path)
        .map_err(|e| e.to_string())?;

    *state.current_audio.lock().unwrap() = Some(info.clone());
    Ok(info)
}

/// 執行剪輯
#[tauri::command]
fn edit_audio(
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

/// 匯出 JSON 報告
#[tauri::command]
fn export_json(report: EditReport, output_path: &str, pretty: bool) -> Result<(), String> {
    Exporter::to_json(&report, output_path, pretty).map_err(|e| e.to_string())
}

/// 匯出 EDL 檔案
#[tauri::command]
fn export_edl(
    report: EditReport,
    output_path: &str,
    fps: f64,
    title: Option<String>,
) -> Result<(), String> {
    Exporter::to_edl(&report, output_path, fps, title.as_deref()).map_err(|e| e.to_string())
}

/// 匯出標記檔案
#[tauri::command]
fn export_markers(report: EditReport, output_path: &str, format: &str) -> Result<(), String> {
    let marker_format = match format {
        "csv" => MarkerFormat::Csv,
        "audacity" | "txt" => MarkerFormat::Audacity,
        _ => MarkerFormat::Csv,
    };

    Exporter::to_markers(&report, output_path, marker_format).map_err(|e| e.to_string())
}

/// 解析移除原因
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

fn main() {
    // 初始化日誌
    tracing_subscriber::fmt::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            get_audio_info,
            edit_audio,
            export_json,
            export_edl,
            export_markers,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
