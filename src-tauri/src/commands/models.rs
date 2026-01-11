//! Model management Tauri commands

use reclip_models::{
    ModelManager,
    registry::{WHISPER_MODELS, DIARIZATION_MODELS},
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};

use crate::state::AppState;

/// Model info for frontend
#[derive(Debug, Clone, Serialize)]
pub struct ModelInfoResponse {
    pub id: String,
    pub name: String,
    pub model_type: String,
    pub size_bytes: u64,
    pub description: String,
    pub is_downloaded: bool,
    pub local_path: Option<String>,
}

/// List all available models
#[tauri::command]
pub async fn list_models(state: State<'_, AppState>) -> Result<Vec<ModelInfoResponse>, String> {
    let manager = state.model_manager.lock().await;

    let mut models = Vec::new();

    // Add Whisper models
    for model in WHISPER_MODELS.iter() {
        let is_downloaded = manager.is_downloaded(model).await;
        let local_path = if is_downloaded {
            Some(manager.model_path(model).to_string_lossy().to_string())
        } else {
            None
        };

        models.push(ModelInfoResponse {
            id: model.id.clone(),
            name: model.name.clone(),
            model_type: "whisper".to_string(),
            size_bytes: model.size_bytes,
            description: model.description.clone(),
            is_downloaded,
            local_path,
        });
    }

    // Add diarization models
    for model in DIARIZATION_MODELS.iter() {
        let is_downloaded = manager.is_downloaded(model).await;
        let local_path = if is_downloaded {
            Some(manager.model_path(model).to_string_lossy().to_string())
        } else {
            None
        };

        models.push(ModelInfoResponse {
            id: model.id.clone(),
            name: model.name.clone(),
            model_type: "diarization".to_string(),
            size_bytes: model.size_bytes,
            description: model.description.clone(),
            is_downloaded,
            local_path,
        });
    }

    Ok(models)
}

/// Get model info by ID
#[tauri::command]
pub async fn get_model_info(
    model_id: String,
    state: State<'_, AppState>,
) -> Result<ModelInfoResponse, String> {
    let manager = state.model_manager.lock().await;

    // Search in Whisper models
    if let Some(model) = WHISPER_MODELS.iter().find(|m| m.id == model_id) {
        let is_downloaded = manager.is_downloaded(model).await;
        let local_path = if is_downloaded {
            Some(manager.model_path(model).to_string_lossy().to_string())
        } else {
            None
        };

        return Ok(ModelInfoResponse {
            id: model.id.clone(),
            name: model.name.clone(),
            model_type: "whisper".to_string(),
            size_bytes: model.size_bytes,
            description: model.description.clone(),
            is_downloaded,
            local_path,
        });
    }

    // Search in diarization models
    if let Some(model) = DIARIZATION_MODELS.iter().find(|m| m.id == model_id) {
        let is_downloaded = manager.is_downloaded(model).await;
        let local_path = if is_downloaded {
            Some(manager.model_path(model).to_string_lossy().to_string())
        } else {
            None
        };

        return Ok(ModelInfoResponse {
            id: model.id.clone(),
            name: model.name.clone(),
            model_type: "diarization".to_string(),
            size_bytes: model.size_bytes,
            description: model.description.clone(),
            is_downloaded,
            local_path,
        });
    }

    Err(format!("Model not found: {}", model_id))
}

/// Download a model
#[tauri::command]
pub async fn download_model(
    model_id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let manager = state.model_manager.lock().await;

    // Find model
    let model = WHISPER_MODELS.iter()
        .chain(DIARIZATION_MODELS.iter())
        .find(|m| m.id == model_id)
        .ok_or_else(|| format!("Model not found: {}", model_id))?
        .clone();

    // Clone for the callback
    let model_id_clone = model_id.clone();

    let path = manager
        .download(&model, move |progress| {
            let _ = app.emit("model:download-progress", serde_json::json!({
                "model_id": model_id_clone,
                "progress": progress,
            }));
        })
        .await
        .map_err(|e| e.to_string())?;

    Ok(path.to_string_lossy().to_string())
}

/// Delete a downloaded model
#[tauri::command]
pub async fn delete_model(
    model_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let manager = state.model_manager.lock().await;

    // Find model
    let model = WHISPER_MODELS.iter()
        .chain(DIARIZATION_MODELS.iter())
        .find(|m| m.id == model_id)
        .ok_or_else(|| format!("Model not found: {}", model_id))?;

    manager.delete(model).await.map_err(|e| e.to_string())
}

/// Get total cache size
#[tauri::command]
pub async fn get_cache_size(state: State<'_, AppState>) -> Result<u64, String> {
    let manager = state.model_manager.lock().await;
    Ok(manager.total_cache_size().await)
}

/// Clear model cache
#[tauri::command]
pub async fn clear_model_cache(state: State<'_, AppState>) -> Result<(), String> {
    let manager = state.model_manager.lock().await;
    manager.clear_cache().await.map_err(|e| e.to_string())
}
