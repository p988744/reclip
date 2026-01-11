import Testing
import Foundation
@testable import ReclipCore

/// ASR 相關測試
@Suite("ASR Tests")
struct ASRTests {

    // MARK: - TranscriptResult Tests

    @Test("TranscriptResult initialization")
    func testTranscriptResultInit() {
        let segments = [
            Segment(text: "Hello", start: 0, end: 1),
            Segment(text: "World", start: 1, end: 2),
        ]

        let result = TranscriptResult(
            segments: segments,
            language: "en",
            duration: 2.0
        )

        #expect(result.segments.count == 2)
        #expect(result.language == "en")
        #expect(result.duration == 2.0)
    }

    @Test("TranscriptResult fullText")
    func testTranscriptResultFullText() {
        let segments = [
            Segment(text: "Hello", start: 0, end: 1),
            Segment(text: "World", start: 1, end: 2),
        ]

        let result = TranscriptResult(
            segments: segments,
            language: "en",
            duration: 2.0
        )

        #expect(result.fullText == "Hello World")
    }

    @Test("TranscriptResult allWords")
    func testTranscriptResultAllWords() {
        let words1 = [
            WordSegment(word: "Hello", start: 0, end: 0.5, confidence: 0.9, speaker: nil),
            WordSegment(word: "there", start: 0.5, end: 1.0, confidence: 0.95, speaker: nil),
        ]
        let words2 = [
            WordSegment(word: "World", start: 1.0, end: 1.5, confidence: 0.88, speaker: nil),
        ]

        let segments = [
            Segment(text: "Hello there", start: 0, end: 1, speaker: nil, words: words1),
            Segment(text: "World", start: 1, end: 2, speaker: nil, words: words2),
        ]

        let result = TranscriptResult(
            segments: segments,
            language: "en",
            duration: 2.0
        )

        #expect(result.allWords.count == 3)
        #expect(result.allWords[0].word == "Hello")
        #expect(result.allWords[2].word == "World")
    }

    // MARK: - Segment Tests

    @Test("Segment initialization")
    func testSegmentInit() {
        let segment = Segment(
            text: "Test segment",
            start: 5.0,
            end: 10.0,
            speaker: "Speaker1",
            words: []
        )

        #expect(segment.text == "Test segment")
        #expect(segment.start == 5.0)
        #expect(segment.end == 10.0)
        #expect(segment.speaker == "Speaker1")
        #expect(segment.duration == 5.0)
    }

    @Test("Segment default speaker is nil")
    func testSegmentDefaultSpeaker() {
        let segment = Segment(text: "Test", start: 0, end: 1)

        #expect(segment.speaker == nil)
        #expect(segment.words.isEmpty)
    }

    // MARK: - WordSegment Tests

    @Test("WordSegment initialization")
    func testWordSegmentInit() {
        let word = WordSegment(
            word: "Hello",
            start: 0.0,
            end: 0.5,
            confidence: 0.95,
            speaker: "Speaker1"
        )

        #expect(word.word == "Hello")
        #expect(word.start == 0.0)
        #expect(word.end == 0.5)
        #expect(word.confidence == 0.95)
        #expect(word.speaker == "Speaker1")
        #expect(word.duration == 0.5)
    }

    @Test("WordSegment default speaker")
    func testWordSegmentDefaultSpeaker() {
        let word = WordSegment(
            word: "Test",
            start: 0,
            end: 1,
            confidence: 0.9,
            speaker: nil
        )

        #expect(word.speaker == nil)
    }

    // MARK: - TranscriptResult Codable Tests

    @Test("TranscriptResult JSON encoding/decoding")
    func testTranscriptResultCodable() throws {
        let words = [
            WordSegment(word: "Hello", start: 0, end: 0.5, confidence: 0.9, speaker: nil),
        ]
        let segments = [
            Segment(text: "Hello", start: 0, end: 1, speaker: nil, words: words),
        ]
        let result = TranscriptResult(
            segments: segments,
            language: "en",
            duration: 1.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TranscriptResult.self, from: data)

        #expect(decoded.language == result.language)
        #expect(decoded.duration == result.duration)
        #expect(decoded.segments.count == result.segments.count)
        #expect(decoded.segments[0].text == result.segments[0].text)
        #expect(decoded.segments[0].words.count == 1)
    }

    // MARK: - Empty TranscriptResult Tests

    @Test("Empty TranscriptResult")
    func testEmptyTranscriptResult() {
        let result = TranscriptResult(
            segments: [],
            language: "zh",
            duration: 0
        )

        #expect(result.segments.isEmpty)
        #expect(result.fullText == "")
        #expect(result.allWords.isEmpty)
    }

    // MARK: - Segment Time Validation Tests

    @Test("Segment time calculations")
    func testSegmentTimeCalculations() {
        let segment = Segment(
            text: "Long segment",
            start: 120.5,  // 2:00.5
            end: 185.75,   // 3:05.75
            speaker: nil,
            words: []
        )

        let expectedDuration = 185.75 - 120.5
        #expect(segment.duration == expectedDuration)
    }

    // MARK: - Word Confidence Range Tests

    @Test("WordSegment confidence values")
    func testWordSegmentConfidenceValues() {
        let lowConfidence = WordSegment(word: "um", start: 0, end: 0.1, confidence: 0.3, speaker: nil)
        let highConfidence = WordSegment(word: "hello", start: 0.1, end: 0.5, confidence: 0.99, speaker: nil)

        #expect(lowConfidence.confidence == 0.3)
        #expect(highConfidence.confidence == 0.99)
    }

    // MARK: - Multi-language Tests

    @Test("TranscriptResult with Chinese text")
    func testChineseTranscript() {
        let segments = [
            Segment(text: "大家好", start: 0, end: 1),
            Segment(text: "歡迎收聽", start: 1, end: 2.5),
        ]

        let result = TranscriptResult(
            segments: segments,
            language: "zh",
            duration: 2.5
        )

        #expect(result.language == "zh")
        #expect(result.fullText == "大家好 歡迎收聽")
    }

    @Test("TranscriptResult with Japanese text")
    func testJapaneseTranscript() {
        let segments = [
            Segment(text: "こんにちは", start: 0, end: 1.5),
        ]

        let result = TranscriptResult(
            segments: segments,
            language: "ja",
            duration: 1.5
        )

        #expect(result.language == "ja")
        #expect(result.fullText == "こんにちは")
    }
}

/// ASR Configuration Tests
@Suite("ASR Configuration Tests")
struct ASRConfigurationTests {

    // Note: ASRConfiguration and ASRError are in ReclipASR module
    // These tests verify the core transcript models work correctly

    @Test("Segment speaker assignment")
    func testSegmentSpeakerAssignment() {
        let segment1 = Segment(text: "Hello", start: 0, end: 1, speaker: "Alice", words: [])
        let segment2 = Segment(text: "Hi there", start: 1, end: 2, speaker: "Bob", words: [])

        #expect(segment1.speaker == "Alice")
        #expect(segment2.speaker == "Bob")
    }

    @Test("Word speaker assignment for diarization")
    func testWordSpeakerAssignment() {
        let word1 = WordSegment(word: "Hello", start: 0, end: 0.5, confidence: 0.9, speaker: "Alice")
        let word2 = WordSegment(word: "Hi", start: 0.5, end: 1.0, confidence: 0.95, speaker: "Bob")

        #expect(word1.speaker == "Alice")
        #expect(word2.speaker == "Bob")
    }
}
