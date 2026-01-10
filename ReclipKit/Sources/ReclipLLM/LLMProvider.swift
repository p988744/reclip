import Foundation
import ReclipCore

/// LLM 提供者協議
public protocol LLMProvider: Sendable {
    /// 提供者名稱
    var name: String { get }

    /// 是否為本地提供者（不需網路）
    var isLocal: Bool { get }

    /// 分析逐字稿並產生剪輯決策
    /// - Parameters:
    ///   - transcript: 轉錄結果
    ///   - configuration: 分析配置
    /// - Returns: 分析結果
    func analyze(
        transcript: TranscriptResult,
        configuration: AnalysisConfiguration
    ) async throws -> AnalysisResult
}

/// LLM 錯誤
public enum LLMError: Error, LocalizedError {
    case connectionFailed(String)
    case invalidResponse(String)
    case rateLimited
    case authenticationFailed
    case modelNotAvailable(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "連線失敗: \(message)"
        case .invalidResponse(let message):
            return "無效回應: \(message)"
        case .rateLimited:
            return "已達 API 速率限制，請稍後再試"
        case .authenticationFailed:
            return "認證失敗，請檢查 API Key"
        case .modelNotAvailable(let model):
            return "模型不可用: \(model)"
        }
    }
}

/// 分析配置
public struct AnalysisConfiguration: Sendable {
    /// 最低信心閾值 (0.0 - 1.0)
    public let minConfidence: Double
    /// 每次分析的最大時長（秒）
    public let maxSegmentDuration: TimeInterval
    /// 要偵測的移除類型
    public let removalTypes: Set<RemovalReason>
    /// 長停頓的閾值（秒）
    public let longPauseThreshold: TimeInterval

    public init(
        minConfidence: Double = 0.7,
        maxSegmentDuration: TimeInterval = 300,
        removalTypes: Set<RemovalReason> = Set(RemovalReason.allCases),
        longPauseThreshold: TimeInterval = 1.5
    ) {
        self.minConfidence = minConfidence
        self.maxSegmentDuration = maxSegmentDuration
        self.removalTypes = removalTypes
        self.longPauseThreshold = longPauseThreshold
    }
}

/// 分析提示模板
public enum AnalysisPrompt {
    /// 產生分析提示
    public static func generate(for segments: [Segment]) -> String {
        let transcriptText = segments.map { segment in
            var line = "[\(String(format: "%.2f", segment.start))-\(String(format: "%.2f", segment.end))]"
            if let speaker = segment.speaker {
                line += " (\(speaker))"
            }
            line += " \(segment.text)"

            // 加入單詞級別資訊
            if !segment.words.isEmpty {
                let wordDetails = segment.words.map { word in
                    "  [\(String(format: "%.2f", word.start))-\(String(format: "%.2f", word.end))] \(word.word)"
                }.joined(separator: "\n")
                line += "\n\(wordDetails)"
            }

            return line
        }.joined(separator: "\n")

        return """
        你是一個專業的 Podcast 剪輯助理。分析以下逐字稿，標記需要移除的區間。

        ## 需要移除的內容類型

        1. **filler** - 語氣詞、填充詞
           - 中文：嗯、啊、呃、那個、就是說、對對對、然後然後、所以說
           - 英文：um, uh, like, you know, so, basically, actually, I mean

        2. **repeat** - 重複的詞語或片語
           - 說話者重複同一個詞或片語多次

        3. **restart** - 句子重新開始
           - 說話者講到一半停下，重新開始說

        4. **mouth_noise** - 唇齒音或雜音
           - 吸氣聲、咂嘴聲、喉音（通常標記為特殊字元或空白）

        5. **long_pause** - 過長的停頓
           - 超過 1.5 秒的停頓（根據時間戳判斷）

        ## 輸入格式

        每行格式：[開始時間-結束時間] (說話者) 文字內容
        時間單位為秒。

        ## 輸出格式

        請以 JSON 格式輸出，包含 removals 陣列：

        ```json
        {
          "removals": [
            {
              "start": 1.23,
              "end": 1.56,
              "reason": "filler",
              "text": "嗯",
              "confidence": 0.95
            }
          ]
        }
        ```

        ## 注意事項

        1. 只標記確定需要移除的內容，不確定就不要標記
        2. 保留有意義的語氣詞（如表達驚訝、認同的「嗯」）
        3. 時間戳必須精確對應輸入中的時間
        4. confidence 範圍 0.0-1.0，表示移除的確定程度
        5. 不要移除可能影響語意的內容

        ## 逐字稿

        \(transcriptText)

        請分析以上逐字稿，輸出 JSON 格式的移除區間。只輸出 JSON，不要有其他說明。
        """
    }
}
