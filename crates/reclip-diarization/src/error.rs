//! Diarization error types

use thiserror::Error;

/// Diarization-related errors
#[derive(Error, Debug)]
pub enum DiarizationError {
    /// Model not loaded
    #[error("Model not loaded. Please load the diarization models first.")]
    ModelNotLoaded,

    /// Model loading failed
    #[error("Failed to load model: {0}")]
    ModelLoadFailed(String),

    /// File not found
    #[error("Audio file not found: {0}")]
    FileNotFound(String),

    /// Diarization failed
    #[error("Diarization failed: {0}")]
    DiarizationFailed(String),

    /// Invalid audio format
    #[error("Invalid audio format: {0}")]
    InvalidAudioFormat(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    /// ONNX Runtime error
    #[error("ONNX Runtime error: {0}")]
    OrtError(String),

    /// No speakers detected
    #[error("No speakers detected in audio")]
    NoSpeakersDetected,
}
