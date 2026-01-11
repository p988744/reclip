//! Ollama local LLM provider

use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{info, debug, warn};

use crate::error::LlmError;
use crate::provider::{LlmProvider, AnalysisRequest, AnalysisResult, AnalysisItem, AnalysisSummary};
use crate::prompts;

const DEFAULT_OLLAMA_URL: &str = "http://localhost:11434";
const DEFAULT_MODEL: &str = "llama3.2";

/// Ollama local LLM provider
pub struct OllamaProvider {
    client: Client,
    base_url: String,
    model: String,
}

impl OllamaProvider {
    /// Create new Ollama provider with default settings
    pub fn new() -> Self {
        Self {
            client: Client::new(),
            base_url: DEFAULT_OLLAMA_URL.to_string(),
            model: DEFAULT_MODEL.to_string(),
        }
    }

    /// Create with custom URL and model
    pub fn with_config(base_url: &str, model: &str) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.to_string(),
            model: model.to_string(),
        }
    }

    /// Set model
    pub fn set_model(&mut self, model: &str) {
        self.model = model.to_string();
    }

    /// Generate response from Ollama
    async fn generate(&self, prompt: &str) -> Result<String, LlmError> {
        let url = format!("{}/api/generate", self.base_url);

        let request = OllamaRequest {
            model: &self.model,
            prompt,
            stream: false,
            options: Some(OllamaOptions {
                temperature: 0.3,
                num_predict: 4096,
            }),
        };

        debug!("Sending request to Ollama at {}", url);

        let response = self.client
            .post(&url)
            .json(&request)
            .send()
            .await
            .map_err(|e| {
                if e.is_connect() {
                    LlmError::ConnectionError(format!(
                        "Cannot connect to Ollama at {}. Is Ollama running?",
                        self.base_url
                    ))
                } else {
                    LlmError::from(e)
                }
            })?;

        let status = response.status();

        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            warn!("Ollama API error: {} - {}", status, error_text);

            if error_text.contains("model") && error_text.contains("not found") {
                return Err(LlmError::ModelNotAvailable(self.model.clone()));
            }

            return Err(LlmError::RequestFailed(format!("{}: {}", status, error_text)));
        }

        let response: OllamaResponse = response.json().await
            .map_err(|e| LlmError::InvalidResponse(e.to_string()))?;

        Ok(response.response)
    }

    /// Parse analysis response
    fn parse_analysis_response(&self, response: &str) -> Result<Vec<AnalysisItem>, LlmError> {
        // Try to extract JSON from response
        let json_str = if let Some(start) = response.find('[') {
            if let Some(end) = response.rfind(']') {
                &response[start..=end]
            } else {
                response
            }
        } else {
            response
        };

        serde_json::from_str(json_str)
            .map_err(|e| LlmError::ParseError(format!("Failed to parse analysis: {}", e)))
    }

    /// List available models
    pub async fn list_models(&self) -> Result<Vec<String>, LlmError> {
        let url = format!("{}/api/tags", self.base_url);

        let response = self.client
            .get(&url)
            .send()
            .await?;

        if !response.status().is_success() {
            return Err(LlmError::RequestFailed("Failed to list models".to_string()));
        }

        let tags: OllamaTagsResponse = response.json().await
            .map_err(|e| LlmError::InvalidResponse(e.to_string()))?;

        Ok(tags.models.into_iter().map(|m| m.name).collect())
    }
}

impl Default for OllamaProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl LlmProvider for OllamaProvider {
    async fn analyze(&self, request: AnalysisRequest) -> Result<AnalysisResult, LlmError> {
        info!("Analyzing transcript with Ollama (model: {})", self.model);

        let prompt = prompts::build_analysis_prompt(&request);
        let response = self.generate(&prompt).await?;
        let items = self.parse_analysis_response(&response)?;

        // Calculate summary
        let total_issues = items.len();
        let mut by_type = std::collections::HashMap::new();
        let mut time_savings = 0.0;

        for item in &items {
            *by_type.entry(item.analysis_type.display_name().to_string()).or_insert(0) += 1;
            time_savings += item.end_time - item.start_time;
        }

        // Calculate quality score
        let duration = items.iter()
            .map(|i| i.end_time)
            .fold(0.0f64, |a, b| a.max(b));

        let issue_density = if duration > 0.0 {
            total_issues as f64 / duration
        } else {
            0.0
        };

        let quality_score = (1.0 - (issue_density * 10.0).min(1.0)) as f32;

        Ok(AnalysisResult {
            items,
            duration,
            summary: AnalysisSummary {
                total_issues,
                by_type,
                time_savings_seconds: time_savings,
                quality_score,
            },
        })
    }

    async fn is_available(&self) -> bool {
        let url = format!("{}/api/tags", self.base_url);
        self.client
            .get(&url)
            .send()
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    }

    fn name(&self) -> &'static str {
        "Ollama"
    }

    fn model(&self) -> &str {
        &self.model
    }
}

#[derive(Serialize)]
struct OllamaRequest<'a> {
    model: &'a str,
    prompt: &'a str,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    options: Option<OllamaOptions>,
}

#[derive(Serialize)]
struct OllamaOptions {
    temperature: f32,
    num_predict: u32,
}

#[derive(Deserialize)]
struct OllamaResponse {
    response: String,
}

#[derive(Deserialize)]
struct OllamaTagsResponse {
    models: Vec<OllamaModel>,
}

#[derive(Deserialize)]
struct OllamaModel {
    name: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let provider = OllamaProvider::new();
        assert_eq!(provider.base_url, DEFAULT_OLLAMA_URL);
        assert_eq!(provider.model, DEFAULT_MODEL);
    }
}
