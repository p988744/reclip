//! LLM integration for reclip
//!
//! This module provides Claude API and Ollama integration for transcript analysis.

pub mod error;
pub mod provider;
pub mod claude;
pub mod ollama;
pub mod prompts;

pub use error::LlmError;
pub use provider::{LlmProvider, AnalysisRequest, AnalysisResult, AnalysisItem, AnalysisType};
pub use claude::ClaudeProvider;
pub use ollama::OllamaProvider;
