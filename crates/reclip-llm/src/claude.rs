//! Claude API provider

use reqwest::Client;
use secrecy::{ExposeSecret, SecretString};
use serde::{Deserialize, Serialize};
use tracing::{info, debug, warn};

use crate::error::LlmError;
use crate::provider::{LlmProvider, AnalysisRequest, AnalysisResult, AnalysisItem, AnalysisSummary};
use crate::prompts;

const CLAUDE_API_URL: &str = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL: &str = "claude-sonnet-4-20250514";
const API_VERSION: &str = "2023-06-01";

/// Claude API provider
pub struct ClaudeProvider {
    client: Client,
    api_key: SecretString,
    model: String,
}

impl ClaudeProvider {
    /// Create new Claude provider
    pub fn new(api_key: SecretString) -> Self {
        Self {
            client: Client::new(),
            api_key,
            model: DEFAULT_MODEL.to_string(),
        }
    }

    /// Create with custom model
    pub fn with_model(api_key: SecretString, model: &str) -> Self {
        Self {
            client: Client::new(),
            api_key,
            model: model.to_string(),
        }
    }

    /// Send message to Claude API
    async fn send_message(&self, prompt: &str) -> Result<String, LlmError> {
        let request = ClaudeRequest {
            model: &self.model,
            max_tokens: 4096,
            messages: vec![ClaudeMessage {
                role: "user",
                content: prompt,
            }],
        };

        debug!("Sending request to Claude API");

        let response = self.client
            .post(CLAUDE_API_URL)
            .header("x-api-key", self.api_key.expose_secret())
            .header("anthropic-version", API_VERSION)
            .header("content-type", "application/json")
            .json(&request)
            .send()
            .await?;

        let status = response.status();

        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            let retry_after = response
                .headers()
                .get("retry-after")
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.parse().ok())
                .unwrap_or(60);
            return Err(LlmError::RateLimited(retry_after));
        }

        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            warn!("Claude API error: {} - {}", status, error_text);
            return Err(LlmError::RequestFailed(format!("{}: {}", status, error_text)));
        }

        let response: ClaudeResponse = response.json().await
            .map_err(|e| LlmError::InvalidResponse(e.to_string()))?;

        response.content
            .first()
            .map(|c| c.text.clone())
            .ok_or_else(|| LlmError::InvalidResponse("Empty response".to_string()))
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
}

impl LlmProvider for ClaudeProvider {
    async fn analyze(&self, request: AnalysisRequest) -> Result<AnalysisResult, LlmError> {
        info!("Analyzing transcript with Claude (model: {})", self.model);

        let prompt = prompts::build_analysis_prompt(&request);
        let response = self.send_message(&prompt).await?;
        let items = self.parse_analysis_response(&response)?;

        // Calculate summary
        let total_issues = items.len();
        let mut by_type = std::collections::HashMap::new();
        let mut time_savings = 0.0;

        for item in &items {
            *by_type.entry(item.analysis_type.display_name().to_string()).or_insert(0) += 1;
            time_savings += item.end_time - item.start_time;
        }

        // Calculate quality score (fewer issues = higher score)
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
        // Try a simple API call to check availability
        let request = ClaudeRequest {
            model: &self.model,
            max_tokens: 10,
            messages: vec![ClaudeMessage {
                role: "user",
                content: "Hello",
            }],
        };

        self.client
            .post(CLAUDE_API_URL)
            .header("x-api-key", self.api_key.expose_secret())
            .header("anthropic-version", API_VERSION)
            .header("content-type", "application/json")
            .json(&request)
            .send()
            .await
            .map(|r| r.status().is_success())
            .unwrap_or(false)
    }

    fn name(&self) -> &'static str {
        "Claude"
    }

    fn model(&self) -> &str {
        &self.model
    }
}

#[derive(Serialize)]
struct ClaudeRequest<'a> {
    model: &'a str,
    max_tokens: u32,
    messages: Vec<ClaudeMessage<'a>>,
}

#[derive(Serialize)]
struct ClaudeMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Deserialize)]
struct ClaudeResponse {
    content: Vec<ClaudeContent>,
}

#[derive(Deserialize)]
struct ClaudeContent {
    text: String,
}
