//! Model management error types

use thiserror::Error;

/// Model management errors
#[derive(Error, Debug)]
pub enum ModelError {
    /// Download failed
    #[error("Download failed: {0}")]
    DownloadFailed(String),

    /// Verification failed
    #[error("Model verification failed: expected {expected}, got {actual}")]
    VerificationFailed {
        expected: String,
        actual: String,
    },

    /// Model not found
    #[error("Model not found: {0}")]
    ModelNotFound(String),

    /// Cache directory error
    #[error("Failed to access cache directory: {0}")]
    CacheDirectoryError(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    /// HTTP error
    #[error("HTTP error: {0}")]
    HttpError(#[from] reqwest::Error),

    /// Invalid model type
    #[error("Invalid model type: {0}")]
    InvalidModelType(String),
}
