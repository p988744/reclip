import Foundation
import ReclipCore

/// ASR 提供者協議
public protocol ASRProvider: Sendable {
    /// 提供者名稱
    var name: String { get }

    /// 是否為本地提供者（不需網路）
    var isLocal: Bool { get }

    /// 支援的語言列表
    var supportedLanguages: [String] { get }

    /// 轉錄音訊檔案
    /// - Parameters:
    ///   - url: 音訊檔案 URL
    ///   - language: 語言代碼 (例如 "zh", "en")
    ///   - includeWordTimestamps: 是否包含單詞級時間戳
    ///   - progress: 進度回調 (0.0 - 1.0)
    /// - Returns: 轉錄結果
    func transcribe(
        url: URL,
        language: String,
        includeWordTimestamps: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptResult
}

/// ASR 錯誤
public enum ASRError: Error, LocalizedError {
    case modelNotLoaded
    case unsupportedLanguage(String)
    case transcriptionFailed(String)
    case fileNotFound(URL)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "模型尚未載入"
        case .unsupportedLanguage(let lang):
            return "不支援的語言: \(lang)"
        case .transcriptionFailed(let message):
            return "轉錄失敗: \(message)"
        case .fileNotFound(let url):
            return "找不到檔案: \(url.lastPathComponent)"
        case .networkError(let error):
            return "網路錯誤: \(error.localizedDescription)"
        }
    }
}

/// ASR 配置
public struct ASRConfiguration: Sendable {
    /// 語言代碼
    public let language: String
    /// 是否包含單詞時間戳
    public let includeWordTimestamps: Bool
    /// 是否啟用說話者分離
    public let enableDiarization: Bool
    /// 最少說話者數（用於 diarization）
    public let minSpeakers: Int?
    /// 最多說話者數（用於 diarization）
    public let maxSpeakers: Int?

    public init(
        language: String = "zh",
        includeWordTimestamps: Bool = true,
        enableDiarization: Bool = true,
        minSpeakers: Int? = nil,
        maxSpeakers: Int? = nil
    ) {
        self.language = language
        self.includeWordTimestamps = includeWordTimestamps
        self.enableDiarization = enableDiarization
        self.minSpeakers = minSpeakers
        self.maxSpeakers = maxSpeakers
    }
}
