//! Speaker diarization module using pyannote-rs
//!
//! This module provides speaker diarization (who spoke when) functionality
//! using the pyannote-rs library with ONNX Runtime inference.

pub mod provider;
pub mod error;
pub mod merger;

pub use provider::{DiarizationProvider, SpeakerSegment, DiarizationResult, DiarizationOptions, DiarizationProgress};
pub use error::DiarizationError;
pub use merger::merge_speakers_with_transcript;

// Re-export types from reclip-core
pub use reclip_core::{TranscriptResult, Segment};
