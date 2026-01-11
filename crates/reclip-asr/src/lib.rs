//! ASR (Automatic Speech Recognition) module using whisper-rs
//!
//! This module provides speech-to-text transcription using the Whisper model
//! with Metal/CoreML acceleration on macOS.

pub mod provider;
pub mod error;
pub mod languages;

pub use provider::{WhisperProvider, TranscriptionOptions, TranscribeProgress};
pub use error::AsrError;
pub use languages::{Language, SUPPORTED_LANGUAGES};

// Re-export types from reclip-core
pub use reclip_core::{TranscriptResult, Segment, WordSegment};
