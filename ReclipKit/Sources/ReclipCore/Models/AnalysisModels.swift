import Foundation

/// 移除原因
public enum RemovalReason: String, Codable, Sendable, CaseIterable {
    /// 語氣詞、填充詞 (嗯、啊、um, uh)
    case filler
    /// 重複的詞語或片語
    case repair
    /// 句子重新開始
    case restart
    /// 唇齒音或雜音
    case mouthNoise = "mouth_noise"
    /// 過長的停頓
    case longPause = "long_pause"

    public var localizedDescription: String {
        switch self {
        case .filler: return "語氣詞"
        case .repair: return "重複"
        case .restart: return "重說"
        case .mouthNoise: return "唇齒音"
        case .longPause: return "長停頓"
        }
    }
}

/// 移除區間
public struct Removal: Codable, Sendable, Identifiable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let reason: RemovalReason
    public let text: String
    public let confidence: Double

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        reason: RemovalReason,
        text: String,
        confidence: Double = 0.9
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.reason = reason
        self.text = text
        self.confidence = confidence
    }

    public var duration: TimeInterval {
        end - start
    }
}

/// 分析結果
public struct AnalysisResult: Codable, Sendable {
    public let removals: [Removal]
    public let originalDuration: TimeInterval
    public let removedDuration: TimeInterval
    public let statistics: [RemovalReason: Int]

    public init(
        removals: [Removal],
        originalDuration: TimeInterval
    ) {
        self.removals = removals
        self.originalDuration = originalDuration
        self.removedDuration = removals.reduce(0) { $0 + $1.duration }

        var stats: [RemovalReason: Int] = [:]
        for removal in removals {
            stats[removal.reason, default: 0] += 1
        }
        self.statistics = stats
    }

    /// 預估編輯後時長
    public var estimatedEditedDuration: TimeInterval {
        originalDuration - removedDuration
    }

    /// 縮減百分比
    public var reductionPercent: Double {
        guard originalDuration > 0 else { return 0 }
        return removedDuration / originalDuration * 100
    }
}
