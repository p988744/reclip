//! 共用類型定義

use serde::{Deserialize, Serialize};

/// 移除原因
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RemovalReason {
    /// 語氣詞、填充詞
    Filler,
    /// 重複的詞語
    Repeat,
    /// 句子重新開始
    Restart,
    /// 唇齒音或雜音
    MouthNoise,
    /// 過長的停頓
    LongPause,
}

impl std::fmt::Display for RemovalReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RemovalReason::Filler => write!(f, "filler"),
            RemovalReason::Repeat => write!(f, "repeat"),
            RemovalReason::Restart => write!(f, "restart"),
            RemovalReason::MouthNoise => write!(f, "mouth_noise"),
            RemovalReason::LongPause => write!(f, "long_pause"),
        }
    }
}

/// 移除區間
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Removal {
    /// 開始時間（秒）
    pub start: f64,
    /// 結束時間（秒）
    pub end: f64,
    /// 移除原因
    pub reason: RemovalReason,
    /// 被移除的文字
    pub text: String,
    /// 信心分數 (0.0 - 1.0)
    pub confidence: f64,
}

impl Removal {
    /// 計算移除區間的時長（秒）
    pub fn duration(&self) -> f64 {
        self.end - self.start
    }
}

/// 已套用的編輯
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppliedEdit {
    /// 原始開始時間（秒）
    pub original_start: f64,
    /// 原始結束時間（秒）
    pub original_end: f64,
    /// 移除原因
    pub reason: String,
    /// 被移除的文字
    pub text: String,
}

/// 分析結果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResult {
    /// 移除區間列表
    pub removals: Vec<Removal>,
    /// 原始時長（秒）
    pub original_duration: f64,
    /// 移除的總時長（秒）
    pub removed_duration: f64,
    /// 統計資訊
    pub statistics: std::collections::HashMap<String, u32>,
}

/// 編輯報告
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditReport {
    /// 輸入檔案路徑
    pub input_path: String,
    /// 輸出檔案路徑
    pub output_path: String,
    /// 原始時長（秒）
    pub original_duration: f64,
    /// 編輯後時長（秒）
    pub edited_duration: f64,
    /// 套用的編輯列表
    pub edits: Vec<AppliedEdit>,
}

/// 單詞級別時間戳
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WordSegment {
    /// 單詞文字
    pub word: String,
    /// 開始時間（秒）
    pub start: f64,
    /// 結束時間（秒）
    pub end: f64,
    /// 信心分數
    pub confidence: f64,
    /// 說話者標識
    pub speaker: Option<String>,
}

/// 句子級別段落
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    /// 文字內容
    pub text: String,
    /// 開始時間（秒）
    pub start: f64,
    /// 結束時間（秒）
    pub end: f64,
    /// 說話者標識
    pub speaker: Option<String>,
    /// 單詞列表
    pub words: Vec<WordSegment>,
}

/// 轉錄結果
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptResult {
    /// 段落列表
    pub segments: Vec<Segment>,
    /// 語言代碼
    pub language: String,
    /// 音訊時長（秒）
    pub duration: f64,
}

/// 音訊資訊
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioInfo {
    /// 檔案路徑
    pub path: String,
    /// 時長（秒）
    pub duration: f64,
    /// 取樣率
    pub sample_rate: u32,
    /// 聲道數
    pub channels: u16,
    /// 位元深度
    pub bits_per_sample: u16,
}
