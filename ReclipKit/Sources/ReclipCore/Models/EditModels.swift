import Foundation

/// 已套用的編輯
public struct AppliedEdit: Codable, Sendable, Identifiable {
    public let id: UUID
    public let originalStart: TimeInterval
    public let originalEnd: TimeInterval
    public let reason: RemovalReason
    public let text: String

    public init(
        id: UUID = UUID(),
        originalStart: TimeInterval,
        originalEnd: TimeInterval,
        reason: RemovalReason,
        text: String
    ) {
        self.id = id
        self.originalStart = originalStart
        self.originalEnd = originalEnd
        self.reason = reason
        self.text = text
    }

    public var duration: TimeInterval {
        originalEnd - originalStart
    }
}

/// 編輯報告
public struct EditReport: Codable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let originalDuration: TimeInterval
    public let editedDuration: TimeInterval
    public let edits: [AppliedEdit]
    public let createdAt: Date

    public init(
        inputURL: URL,
        outputURL: URL,
        originalDuration: TimeInterval,
        editedDuration: TimeInterval,
        edits: [AppliedEdit],
        createdAt: Date = Date()
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.originalDuration = originalDuration
        self.editedDuration = editedDuration
        self.edits = edits
        self.createdAt = createdAt
    }

    /// 移除的總時長
    public var removedDuration: TimeInterval {
        originalDuration - editedDuration
    }

    /// 縮減百分比
    public var reductionPercent: Double {
        guard originalDuration > 0 else { return 0 }
        return removedDuration / originalDuration * 100
    }

    /// 統計各原因的數量
    public var statistics: [RemovalReason: Int] {
        var stats: [RemovalReason: Int] = [:]
        for edit in edits {
            stats[edit.reason, default: 0] += 1
        }
        return stats
    }
}

/// 音訊資訊
public struct AudioInfo: Codable, Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int

    public init(
        url: URL,
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int
    ) {
        self.url = url
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}
