//! LLM provider trait and common types

use serde::{Deserialize, Serialize};
use crate::error::LlmError;

/// Analysis type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnalysisType {
    /// Filler words (um, uh, like, you know)
    FillerWord,
    /// Repeated words or phrases
    Repetition,
    /// False starts or corrections
    FalseStart,
    /// Long pauses
    LongPause,
    /// Stuttering
    Stutter,
    /// Off-topic tangent
    Tangent,
}

impl AnalysisType {
    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            AnalysisType::FillerWord => "Filler Word",
            AnalysisType::Repetition => "Repetition",
            AnalysisType::FalseStart => "False Start",
            AnalysisType::LongPause => "Long Pause",
            AnalysisType::Stutter => "Stutter",
            AnalysisType::Tangent => "Tangent",
        }
    }

    /// Get severity weight (for scoring)
    pub fn severity_weight(&self) -> f32 {
        match self {
            AnalysisType::FillerWord => 0.3,
            AnalysisType::Repetition => 0.5,
            AnalysisType::FalseStart => 0.6,
            AnalysisType::LongPause => 0.4,
            AnalysisType::Stutter => 0.5,
            AnalysisType::Tangent => 0.8,
        }
    }
}

/// Single analysis item
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisItem {
    /// Type of issue
    pub analysis_type: AnalysisType,
    /// Start time in seconds
    pub start_time: f64,
    /// End time in seconds
    pub end_time: f64,
    /// Original text
    pub original_text: String,
    /// Suggested replacement (if applicable)
    pub suggested_replacement: Option<String>,
    /// Confidence score (0.0 - 1.0)
    pub confidence: f32,
    /// Reason for flagging
    pub reason: String,
}

/// Analysis request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisRequest {
    /// Transcript text with timestamps
    pub transcript: String,
    /// Language code
    pub language: String,
    /// Speaker labels (if available)
    pub speakers: Option<Vec<String>>,
    /// Analysis types to perform
    pub analysis_types: Vec<AnalysisType>,
    /// Sensitivity level (0.0 = lenient, 1.0 = strict)
    pub sensitivity: f32,
}

impl Default for AnalysisRequest {
    fn default() -> Self {
        Self {
            transcript: String::new(),
            language: "en".to_string(),
            speakers: None,
            analysis_types: vec![
                AnalysisType::FillerWord,
                AnalysisType::Repetition,
                AnalysisType::FalseStart,
                AnalysisType::LongPause,
            ],
            sensitivity: 0.5,
        }
    }
}

/// Analysis result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResult {
    /// List of analysis items
    pub items: Vec<AnalysisItem>,
    /// Total duration analyzed
    pub duration: f64,
    /// Summary statistics
    pub summary: AnalysisSummary,
}

/// Analysis summary
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisSummary {
    /// Total number of issues found
    pub total_issues: usize,
    /// Issues by type
    pub by_type: std::collections::HashMap<String, usize>,
    /// Estimated time savings if all issues are edited
    pub time_savings_seconds: f64,
    /// Quality score (0.0 - 1.0, higher is better)
    pub quality_score: f32,
}

/// LLM provider trait
#[trait_variant::make(LlmProvider: Send)]
pub trait LocalLlmProvider {
    /// Analyze transcript
    async fn analyze(
        &self,
        request: AnalysisRequest,
    ) -> Result<AnalysisResult, LlmError>;

    /// Check if provider is available
    async fn is_available(&self) -> bool;

    /// Get provider name
    fn name(&self) -> &'static str;

    /// Get model name
    fn model(&self) -> &str;
}

/// Streaming callback for analysis progress
pub type AnalysisProgressCallback = Box<dyn Fn(f64, Option<&str>) + Send + Sync>;
