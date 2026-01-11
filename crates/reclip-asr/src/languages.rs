//! Supported languages for ASR

use serde::{Deserialize, Serialize};

/// Language information
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Language {
    /// Language code (e.g., "zh", "en")
    pub code: &'static str,
    /// Display name (e.g., "簡體中文", "English")
    pub name: &'static str,
    /// Whisper language code (may differ from code)
    pub whisper_code: &'static str,
}

/// Supported languages list
pub static SUPPORTED_LANGUAGES: &[Language] = &[
    Language {
        code: "zh",
        name: "簡體中文",
        whisper_code: "zh",
    },
    Language {
        code: "zh-TW",
        name: "台灣中文",
        whisper_code: "zh",
    },
    Language {
        code: "zh-HK",
        name: "香港中文",
        whisper_code: "zh",
    },
    Language {
        code: "yue",
        name: "粵語",
        whisper_code: "yue",
    },
    Language {
        code: "en",
        name: "English",
        whisper_code: "en",
    },
    Language {
        code: "ja",
        name: "日本語",
        whisper_code: "ja",
    },
    Language {
        code: "ko",
        name: "한국어",
        whisper_code: "ko",
    },
    Language {
        code: "es",
        name: "Español",
        whisper_code: "es",
    },
    Language {
        code: "fr",
        name: "Français",
        whisper_code: "fr",
    },
    Language {
        code: "de",
        name: "Deutsch",
        whisper_code: "de",
    },
    Language {
        code: "it",
        name: "Italiano",
        whisper_code: "it",
    },
    Language {
        code: "pt",
        name: "Português",
        whisper_code: "pt",
    },
    Language {
        code: "ru",
        name: "Русский",
        whisper_code: "ru",
    },
    Language {
        code: "ar",
        name: "العربية",
        whisper_code: "ar",
    },
    Language {
        code: "hi",
        name: "हिन्दी",
        whisper_code: "hi",
    },
];

impl Language {
    /// Map user-selected language code to Whisper's language code
    pub fn to_whisper_code(code: &str) -> &'static str {
        SUPPORTED_LANGUAGES
            .iter()
            .find(|l| l.code == code)
            .map(|l| l.whisper_code)
            .unwrap_or("en")
    }

    /// Check if a language is supported
    pub fn is_supported(code: &str) -> bool {
        SUPPORTED_LANGUAGES.iter().any(|l| l.code == code)
    }

    /// Get language info by code
    pub fn get(code: &str) -> Option<&'static Language> {
        SUPPORTED_LANGUAGES.iter().find(|l| l.code == code)
    }
}
