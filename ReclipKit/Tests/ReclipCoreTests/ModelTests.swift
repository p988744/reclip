import XCTest
@testable import ReclipCore

final class ModelTests: XCTestCase {
    func testWordSegmentDuration() {
        let word = WordSegment(
            word: "test",
            start: 1.0,
            end: 1.5,
            confidence: 0.9
        )

        XCTAssertEqual(word.duration, 0.5, accuracy: 0.001)
    }

    func testRemovalDuration() {
        let removal = Removal(
            start: 1.0,
            end: 2.5,
            reason: .filler,
            text: "嗯",
            confidence: 0.95
        )

        XCTAssertEqual(removal.duration, 1.5, accuracy: 0.001)
    }

    func testAnalysisResultStatistics() {
        let removals = [
            Removal(start: 0, end: 1, reason: .filler, text: "嗯"),
            Removal(start: 2, end: 3, reason: .filler, text: "啊"),
            Removal(start: 4, end: 5, reason: .repair, text: "重複"),
        ]

        let result = AnalysisResult(
            removals: removals,
            originalDuration: 60.0
        )

        XCTAssertEqual(result.statistics[.filler], 2)
        XCTAssertEqual(result.statistics[.repair], 1)
        XCTAssertEqual(result.removedDuration, 3.0, accuracy: 0.001)
    }

    func testEditReportReductionPercent() {
        let report = EditReport(
            inputURL: URL(fileURLWithPath: "/input.wav"),
            outputURL: URL(fileURLWithPath: "/output.wav"),
            originalDuration: 100.0,
            editedDuration: 90.0,
            edits: []
        )

        XCTAssertEqual(report.reductionPercent, 10.0, accuracy: 0.001)
    }

    func testTranscriptFullText() {
        let segments = [
            Segment(text: "Hello", start: 0, end: 1),
            Segment(text: "World", start: 1, end: 2),
        ]

        let transcript = TranscriptResult(
            segments: segments,
            language: "en",
            duration: 2.0
        )

        XCTAssertEqual(transcript.fullText, "Hello World")
    }
}
