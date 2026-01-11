//! LLM analysis Tauri commands

use reclip_llm::{
    ClaudeProvider, OllamaProvider, LlmProvider,
    AnalysisRequest, AnalysisResult, AnalysisType,
};
use secrecy::SecretString;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};

use crate::state::AppState;

/// LLM provider type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LlmProviderType {
    Claude,
    Ollama,
}

/// LLM configuration from frontend
#[derive(Debug, Deserialize)]
pub struct LlmConfigInput {
    pub provider: LlmProviderType,
    pub api_key: Option<String>,
    pub model: Option<String>,
    pub ollama_url: Option<String>,
}

/// LLM status for frontend
#[derive(Debug, Clone, Serialize)]
pub struct LlmStatus {
    pub provider: Option<String>,
    pub model: String,
    pub is_available: bool,
}

/// Analysis options from frontend
#[derive(Debug, Deserialize)]
pub struct AnalysisOptionsInput {
    pub transcript: String,
    pub language: String,
    pub speakers: Option<Vec<String>>,
    pub sensitivity: Option<f32>,
    pub analysis_types: Option<Vec<String>>,
}

/// Configure LLM provider
#[tauri::command]
pub async fn configure_llm(
    config: LlmConfigInput,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut llm_state = state.llm_state.lock().await;

    match config.provider {
        LlmProviderType::Claude => {
            let api_key = config.api_key
                .ok_or("API key required for Claude")?;
            let provider = if let Some(model) = config.model {
                ClaudeProvider::with_model(SecretString::new(api_key.into()), &model)
            } else {
                ClaudeProvider::new(SecretString::new(api_key.into()))
            };
            llm_state.claude_provider = Some(provider);
            llm_state.current_provider = Some(LlmProviderType::Claude);
        }
        LlmProviderType::Ollama => {
            let url = config.ollama_url.unwrap_or_else(|| "http://localhost:11434".to_string());
            let model = config.model.unwrap_or_else(|| "llama3.2".to_string());
            let provider = OllamaProvider::with_config(&url, &model);
            llm_state.ollama_provider = Some(provider);
            llm_state.current_provider = Some(LlmProviderType::Ollama);
        }
    }

    Ok(())
}

/// Get LLM status
#[tauri::command]
pub async fn get_llm_status(state: State<'_, AppState>) -> Result<LlmStatus, String> {
    let llm_state = state.llm_state.lock().await;

    match llm_state.current_provider {
        Some(LlmProviderType::Claude) => {
            if let Some(provider) = &llm_state.claude_provider {
                Ok(LlmStatus {
                    provider: Some("Claude".to_string()),
                    model: provider.model().to_string(),
                    is_available: provider.is_available().await,
                })
            } else {
                Ok(LlmStatus {
                    provider: None,
                    model: String::new(),
                    is_available: false,
                })
            }
        }
        Some(LlmProviderType::Ollama) => {
            if let Some(provider) = &llm_state.ollama_provider {
                Ok(LlmStatus {
                    provider: Some("Ollama".to_string()),
                    model: provider.model().to_string(),
                    is_available: provider.is_available().await,
                })
            } else {
                Ok(LlmStatus {
                    provider: None,
                    model: String::new(),
                    is_available: false,
                })
            }
        }
        None => Ok(LlmStatus {
            provider: None,
            model: String::new(),
            is_available: false,
        }),
    }
}

/// List available Ollama models
#[tauri::command]
pub async fn list_ollama_models(state: State<'_, AppState>) -> Result<Vec<String>, String> {
    let llm_state = state.llm_state.lock().await;

    if let Some(provider) = &llm_state.ollama_provider {
        provider.list_models().await.map_err(|e| e.to_string())
    } else {
        // Try with default connection
        let provider = OllamaProvider::new();
        provider.list_models().await.map_err(|e| e.to_string())
    }
}

/// Analyze transcript with LLM
#[tauri::command]
pub async fn analyze_transcript(
    options: AnalysisOptionsInput,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<AnalysisResult, String> {
    let llm_state = state.llm_state.lock().await;

    // Parse analysis types
    let analysis_types = options.analysis_types
        .map(|types| {
            types.iter()
                .filter_map(|t| parse_analysis_type(t))
                .collect()
        })
        .unwrap_or_else(|| vec![
            AnalysisType::FillerWord,
            AnalysisType::Repetition,
            AnalysisType::FalseStart,
            AnalysisType::LongPause,
        ]);

    let request = AnalysisRequest {
        transcript: options.transcript,
        language: options.language,
        speakers: options.speakers,
        analysis_types,
        sensitivity: options.sensitivity.unwrap_or(0.5),
    };

    // Emit start event
    let _ = app.emit("llm:analysis-start", ());

    let result = match llm_state.current_provider {
        Some(LlmProviderType::Claude) => {
            let provider = llm_state.claude_provider.as_ref()
                .ok_or("Claude provider not configured")?;
            provider.analyze(request).await
        }
        Some(LlmProviderType::Ollama) => {
            let provider = llm_state.ollama_provider.as_ref()
                .ok_or("Ollama provider not configured")?;
            provider.analyze(request).await
        }
        None => return Err("No LLM provider configured".to_string()),
    };

    // Emit complete event
    let _ = app.emit("llm:analysis-complete", ());

    result.map_err(|e| e.to_string())
}

/// Parse analysis type string
fn parse_analysis_type(s: &str) -> Option<AnalysisType> {
    match s {
        "filler_word" | "filler" => Some(AnalysisType::FillerWord),
        "repetition" | "repeat" => Some(AnalysisType::Repetition),
        "false_start" | "restart" => Some(AnalysisType::FalseStart),
        "long_pause" | "pause" => Some(AnalysisType::LongPause),
        "stutter" => Some(AnalysisType::Stutter),
        "tangent" => Some(AnalysisType::Tangent),
        _ => None,
    }
}
