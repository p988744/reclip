//! Model download and cache management for reclip
//!
//! This module handles downloading, caching, and verification of ML models
//! from HuggingFace and other sources.

pub mod manager;
pub mod error;
pub mod registry;

pub use manager::{ModelManager, DownloadProgress};
pub use error::ModelError;
pub use registry::{ModelInfo, ModelType, WHISPER_MODELS, DIARIZATION_MODELS};
