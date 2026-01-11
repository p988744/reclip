//! Waveform generation error types

use thiserror::Error;

/// Waveform-related errors
#[derive(Error, Debug)]
pub enum WaveformError {
    /// File not found
    #[error("Audio file not found: {0}")]
    FileNotFound(String),

    /// Invalid audio format
    #[error("Invalid audio format: {0}")]
    InvalidFormat(String),

    /// Generation failed
    #[error("Waveform generation failed: {0}")]
    GenerationFailed(String),

    /// Cache error
    #[error("Cache error: {0}")]
    CacheError(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),
}
