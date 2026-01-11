//! LLM error types

use thiserror::Error;

/// LLM-related errors
#[derive(Error, Debug)]
pub enum LlmError {
    /// API key not configured
    #[error("API key not configured")]
    ApiKeyMissing,

    /// API request failed
    #[error("API request failed: {0}")]
    RequestFailed(String),

    /// Invalid response from API
    #[error("Invalid API response: {0}")]
    InvalidResponse(String),

    /// Rate limit exceeded
    #[error("Rate limit exceeded, retry after {0} seconds")]
    RateLimited(u64),

    /// Model not available
    #[error("Model not available: {0}")]
    ModelNotAvailable(String),

    /// Connection error
    #[error("Connection error: {0}")]
    ConnectionError(String),

    /// Parse error
    #[error("Failed to parse response: {0}")]
    ParseError(String),

    /// Timeout
    #[error("Request timed out")]
    Timeout,

    /// Configuration error
    #[error("Configuration error: {0}")]
    ConfigError(String),
}

impl From<reqwest::Error> for LlmError {
    fn from(err: reqwest::Error) -> Self {
        if err.is_timeout() {
            LlmError::Timeout
        } else if err.is_connect() {
            LlmError::ConnectionError(err.to_string())
        } else {
            LlmError::RequestFailed(err.to_string())
        }
    }
}
