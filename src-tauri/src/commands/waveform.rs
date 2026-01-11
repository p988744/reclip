//! Waveform generation Tauri commands

use reclip_waveform::{WaveformGenerator, WaveformData, WaveformResolution};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};

use crate::state::AppState;

/// Waveform options from frontend
#[derive(Debug, Deserialize)]
pub struct WaveformOptionsInput {
    pub resolution: Option<String>,
    pub use_cache: Option<bool>,
}

/// Generate waveform data
#[tauri::command]
pub async fn generate_waveform(
    audio_path: String,
    options: Option<WaveformOptionsInput>,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<WaveformData, String> {
    let opts = options.unwrap_or(WaveformOptionsInput {
        resolution: None,
        use_cache: None,
    });

    let resolution = match opts.resolution.as_deref() {
        Some("thumbnail") => WaveformResolution::Thumbnail,
        Some("standard") => WaveformResolution::Standard,
        Some("high") => WaveformResolution::High,
        Some("full") => WaveformResolution::Full,
        _ => WaveformResolution::Standard,
    };

    let use_cache = opts.use_cache.unwrap_or(true);
    let generator = state.waveform_generator.lock().await;

    generator
        .generate(&audio_path, resolution, use_cache, move |progress| {
            let _ = app.emit("waveform:progress", progress);
        })
        .await
        .map_err(|e| e.to_string())
}

/// Generate thumbnail waveform (fast)
#[tauri::command]
pub async fn generate_thumbnail_waveform(
    audio_path: String,
    state: State<'_, AppState>,
) -> Result<WaveformData, String> {
    let generator = state.waveform_generator.lock().await;
    generator
        .generate_thumbnail(&audio_path)
        .await
        .map_err(|e| e.to_string())
}

/// Clear waveform cache
#[tauri::command]
pub async fn clear_waveform_cache(state: State<'_, AppState>) -> Result<(), String> {
    let generator = state.waveform_generator.lock().await;
    generator.clear_cache().await.map_err(|e| e.to_string())
}
