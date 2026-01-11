//! ASR error types

use thiserror::Error;

/// ASR-related errors
#[derive(Error, Debug)]
pub enum AsrError {
    /// Model not loaded
    #[error("Model not loaded. Please load a model first.")]
    ModelNotLoaded,

    /// Model loading failed
    #[error("Failed to load model: {0}")]
    ModelLoadFailed(String),

    /// Unsupported language
    #[error("Unsupported language: {0}")]
    UnsupportedLanguage(String),

    /// File not found
    #[error("Audio file not found: {0}")]
    FileNotFound(String),

    /// Transcription failed
    #[error("Transcription failed: {0}")]
    TranscriptionFailed(String),

    /// Invalid audio format
    #[error("Invalid audio format: {0}")]
    InvalidAudioFormat(String),

    /// IO error
    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    /// Whisper error
    #[error("Whisper error: {0}")]
    WhisperError(String),
}
