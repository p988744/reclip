//! reclip-core - Podcast 自動剪輯核心庫
//!
//! 提供音訊處理、剪輯、匯出等功能。

pub mod audio;
pub mod editor;
pub mod exporter;
pub mod types;

#[cfg(feature = "python")]
pub mod python;

pub use audio::AudioProcessor;
pub use editor::Editor;
pub use exporter::Exporter;
pub use types::*;
