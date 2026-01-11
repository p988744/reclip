//! Speaker diarization Tauri commands

use reclip_diarization::{
    DiarizationProvider, DiarizationOptions, DiarizationResult,
    DiarizationProgress, SpeakerSegment,
    merger::merge_speakers_with_transcript,
};
use reclip_core::TranscriptResult;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};

use crate::state::AppState;

/// Diarization model info for frontend
#[derive(Debug, Clone, Serialize)]
pub struct DiarizationModelInfo {
    pub is_loaded: bool,
}

/// Diarization options from frontend
#[derive(Debug, Deserialize)]
pub struct DiarizationOptionsInput {
    pub min_speakers: Option<u32>,
    pub max_speakers: Option<u32>,
}

/// Get diarization model status
#[tauri::command]
pub async fn get_diarization_status(state: State<'_, AppState>) -> Result<DiarizationModelInfo, String> {
    let provider = state.diarization_provider.lock().await;
    Ok(DiarizationModelInfo {
        is_loaded: provider.is_loaded(),
    })
}

/// Load diarization models
#[tauri::command]
pub async fn load_diarization_models(
    segmentation_model_path: String,
    embedding_model_path: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut provider = state.diarization_provider.lock().await;

    provider
        .load_models(&segmentation_model_path, &embedding_model_path, move |progress| {
            let _ = app.emit("diarization:model-loading", progress);
        })
        .await
        .map_err(|e| e.to_string())
}

/// Unload diarization models
#[tauri::command]
pub async fn unload_diarization_models(state: State<'_, AppState>) -> Result<(), String> {
    let mut provider = state.diarization_provider.lock().await;
    provider.unload();
    Ok(())
}

/// Run speaker diarization
#[tauri::command]
pub async fn diarize(
    audio_path: String,
    options: Option<DiarizationOptionsInput>,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<DiarizationResult, String> {
    let provider = state.diarization_provider.lock().await;

    let opts = options.unwrap_or(DiarizationOptionsInput {
        min_speakers: None,
        max_speakers: None,
    });

    let diarization_options = DiarizationOptions {
        min_speakers: opts.min_speakers,
        max_speakers: opts.max_speakers,
    };

    provider
        .diarize(&audio_path, diarization_options, move |progress| {
            let _ = app.emit("diarization:progress", progress);
        })
        .await
        .map_err(|e| e.to_string())
}

/// Merge speaker labels with transcript
#[tauri::command]
pub fn merge_speakers(
    transcript: TranscriptResult,
    diarization: DiarizationResult,
) -> Result<TranscriptResult, String> {
    merge_speakers_with_transcript(transcript, &diarization.segments)
        .map_err(|e| e.to_string())
}
