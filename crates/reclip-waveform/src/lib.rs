//! Waveform generation for reclip
//!
//! This module provides multi-resolution waveform generation for audio visualization.

pub mod generator;
pub mod error;

pub use generator::{WaveformGenerator, WaveformData, WaveformResolution};
pub use error::WaveformError;
