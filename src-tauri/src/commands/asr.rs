//! ASR (Automatic Speech Recognition) Tauri commands

use reclip_asr::{
    TranscriptionOptions,
    languages::SUPPORTED_LANGUAGES,
};
use reclip_core::TranscriptResult;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};

use crate::state::AppState;

/// ASR model info for frontend
#[derive(Debug, Clone, Serialize)]
pub struct AsrModelInfo {
    pub is_loaded: bool,
    pub model_path: Option<String>,
}

/// Transcription options from frontend
#[derive(Debug, Deserialize)]
pub struct TranscriptionOptionsInput {
    pub language: Option<String>,
    pub word_timestamps: Option<bool>,
    pub threads: Option<u32>,
}

/// Language info for frontend
#[derive(Debug, Clone, Serialize)]
pub struct LanguageInfo {
    pub code: &'static str,
    pub name: &'static str,
}

/// Get supported languages
#[tauri::command]
pub fn get_languages() -> Vec<LanguageInfo> {
    SUPPORTED_LANGUAGES
        .iter()
        .map(|l| LanguageInfo {
            code: l.code,
            name: l.name,
        })
        .collect()
}

/// Get ASR model status
#[tauri::command]
pub async fn get_asr_status(state: State<'_, AppState>) -> Result<AsrModelInfo, String> {
    let provider = state.asr_provider.lock().await;
    Ok(AsrModelInfo {
        is_loaded: provider.is_loaded(),
        model_path: provider.model_path().map(|s| s.to_string()),
    })
}

/// Load ASR model
#[tauri::command]
pub async fn load_asr_model(
    model_path: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut provider = state.asr_provider.lock().await;

    provider
        .load_model(&model_path, move |progress| {
            let _ = app.emit("asr:model-loading", progress);
        })
        .await
        .map_err(|e| e.to_string())
}

/// Unload ASR model
#[tauri::command]
pub async fn unload_asr_model(state: State<'_, AppState>) -> Result<(), String> {
    let mut provider = state.asr_provider.lock().await;
    provider.unload();
    Ok(())
}

/// Transcribe audio file
#[tauri::command]
pub async fn transcribe(
    audio_path: String,
    options: Option<TranscriptionOptionsInput>,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<TranscriptResult, String> {
    let provider = state.asr_provider.lock().await;

    let opts = options.unwrap_or(TranscriptionOptionsInput {
        language: None,
        word_timestamps: None,
        threads: None,
    });

    let transcription_options = TranscriptionOptions {
        language: opts.language.unwrap_or_else(|| "zh".to_string()),
        word_timestamps: opts.word_timestamps.unwrap_or(true),
        threads: opts.threads.unwrap_or(0),
    };

    provider
        .transcribe(&audio_path, transcription_options, move |progress| {
            // Emit progress event to frontend
            let _ = app.emit("asr:transcribe-progress", &progress);
        })
        .await
        .map_err(|e| e.to_string())
}
