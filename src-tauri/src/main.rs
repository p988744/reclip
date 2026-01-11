//! Reclip Tauri 桌面應用
//!
//! 使用 Tauri 2.0 建立的跨平台桌面應用

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod state;

use state::AppState;

fn main() {
    // 初始化日誌
    tracing_subscriber::fmt::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            // Audio commands
            commands::audio::get_audio_info,
            commands::audio::edit_audio,
            commands::audio::export_json,
            commands::audio::export_edl,
            commands::audio::export_markers,
            // ASR commands
            commands::asr::get_languages,
            commands::asr::get_asr_status,
            commands::asr::load_asr_model,
            commands::asr::unload_asr_model,
            commands::asr::transcribe,
            // Diarization commands
            commands::diarization::get_diarization_status,
            commands::diarization::load_diarization_models,
            commands::diarization::unload_diarization_models,
            commands::diarization::diarize,
            commands::diarization::merge_speakers,
            // LLM commands
            commands::llm::configure_llm,
            commands::llm::get_llm_status,
            commands::llm::list_ollama_models,
            commands::llm::analyze_transcript,
            // Waveform commands
            commands::waveform::generate_waveform,
            commands::waveform::generate_thumbnail_waveform,
            commands::waveform::clear_waveform_cache,
            // Model commands
            commands::models::list_models,
            commands::models::get_model_info,
            commands::models::download_model,
            commands::models::delete_model,
            commands::models::get_cache_size,
            commands::models::clear_model_cache,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
