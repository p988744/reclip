import Foundation

/// 單詞級別時間戳
public struct WordSegment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let word: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double
    public let speaker: String?

    public init(
        id: UUID = UUID(),
        word: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double = 1.0,
        speaker: String? = nil
    ) {
        self.id = id
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
        self.speaker = speaker
    }

    public var duration: TimeInterval {
        end - start
    }
}

/// 句子級別段落
public struct Segment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let speaker: String?
    public let words: [WordSegment]

    public init(
        id: UUID = UUID(),
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        speaker: String? = nil,
        words: [WordSegment] = []
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
        self.words = words
    }

    public var duration: TimeInterval {
        end - start
    }
}

/// 轉錄結果
public struct TranscriptResult: Codable, Sendable {
    public let segments: [Segment]
    public let language: String
    public let duration: TimeInterval

    public init(
        segments: [Segment],
        language: String,
        duration: TimeInterval
    ) {
        self.segments = segments
        self.language = language
        self.duration = duration
    }

    /// 取得完整文字
    public var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    /// 取得所有單詞
    public var allWords: [WordSegment] {
        segments.flatMap(\.words)
    }
}
