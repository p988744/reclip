import Testing
import Foundation
@testable import ReclipCore

/// AudioEditor 測試
@Suite("AudioEditor Tests")
struct AudioEditorTests {

    // MARK: - Configuration Tests

    @Test("Default configuration values")
    func testDefaultConfiguration() {
        let config = AudioEditor.Configuration()

        #expect(config.crossfadeDuration == 0.03)
        #expect(config.minRemovalDuration == 0.1)
        #expect(config.mergeGap == 0.05)
        #expect(config.zeroCrossingSearchRange == 0.005)
    }

    @Test("Custom configuration values")
    func testCustomConfiguration() {
        let config = AudioEditor.Configuration(
            crossfadeDuration: 0.05,
            minRemovalDuration: 0.2,
            mergeGap: 0.1,
            zeroCrossingSearchRange: 0.01
        )

        #expect(config.crossfadeDuration == 0.05)
        #expect(config.minRemovalDuration == 0.2)
        #expect(config.mergeGap == 0.1)
        #expect(config.zeroCrossingSearchRange == 0.01)
    }

    // MARK: - AudioInfo Tests

    @Test("AudioInfo initialization")
    func testAudioInfoInit() {
        let url = URL(fileURLWithPath: "/test/audio.wav")
        let info = AudioInfo(
            url: url,
            duration: 120.5,
            sampleRate: 48000,
            channelCount: 2
        )

        #expect(info.url == url)
        #expect(info.duration == 120.5)
        #expect(info.sampleRate == 48000)
        #expect(info.channelCount == 2)
    }

    // MARK: - Error Tests

    @Test("AudioEditorError descriptions")
    func testErrorDescriptions() {
        let noTrack = AudioEditorError.noAudioTrack
        #expect(noTrack.errorDescription == "找不到音訊軌道")

        let invalidFormat = AudioEditorError.invalidFormat
        #expect(invalidFormat.errorDescription == "無效的音訊格式")

        let compositionFailed = AudioEditorError.compositionFailed
        #expect(compositionFailed.errorDescription == "無法建立 composition")

        let exportFailed = AudioEditorError.exportFailed("測試錯誤")
        #expect(exportFailed.errorDescription == "匯出失敗: 測試錯誤")

        let fileNotFound = AudioEditorError.fileNotFound(URL(fileURLWithPath: "/test.wav"))
        #expect(fileNotFound.errorDescription == "找不到檔案: test.wav")
    }
}

/// AppliedEdit 測試
@Suite("AppliedEdit Tests")
struct AppliedEditTests {

    @Test("AppliedEdit initialization")
    func testAppliedEditInit() {
        let edit = AppliedEdit(
            originalStart: 10.0,
            originalEnd: 15.0,
            reason: .filler,
            text: "嗯"
        )

        #expect(edit.originalStart == 10.0)
        #expect(edit.originalEnd == 15.0)
        #expect(edit.reason == .filler)
        #expect(edit.text == "嗯")
        #expect(edit.duration == 5.0)
    }

    @Test("AppliedEdit with custom ID")
    func testAppliedEditWithCustomID() {
        let customID = UUID()
        let edit = AppliedEdit(
            id: customID,
            originalStart: 5.0,
            originalEnd: 8.0,
            reason: .repair,
            text: "就是說"
        )

        #expect(edit.id == customID)
        #expect(edit.duration == 3.0)
    }
}

/// Removal 測試
@Suite("Removal Tests")
struct RemovalTests {

    @Test("Removal initialization")
    func testRemovalInit() {
        let removal = Removal(
            start: 5.0,
            end: 7.5,
            reason: .filler,
            text: "嗯"
        )

        #expect(removal.start == 5.0)
        #expect(removal.end == 7.5)
        #expect(removal.reason == .filler)
        #expect(removal.text == "嗯")
        #expect(removal.confidence == 0.9) // 預設 confidence 為 0.9
        #expect(removal.duration == 2.5)
    }

    @Test("Removal with custom confidence")
    func testRemovalWithConfidence() {
        let removal = Removal(
            start: 10.0,
            end: 12.0,
            reason: .repair,
            text: "就是說",
            confidence: 0.85
        )

        #expect(removal.confidence == 0.85)
    }

    @Test("RemovalReason raw values")
    func testRemovalReasonRawValues() {
        #expect(RemovalReason.filler.rawValue == "filler")
        #expect(RemovalReason.repair.rawValue == "repair")
        #expect(RemovalReason.restart.rawValue == "restart")
        #expect(RemovalReason.mouthNoise.rawValue == "mouth_noise")
        #expect(RemovalReason.longPause.rawValue == "long_pause")
    }
}

/// AnalysisResult 測試
@Suite("AnalysisResult Tests")
struct AnalysisResultTests {

    @Test("AnalysisResult statistics")
    func testAnalysisResultStatistics() {
        let removals = [
            Removal(start: 0, end: 1, reason: .filler, text: "嗯"),
            Removal(start: 2, end: 3, reason: .filler, text: "啊"),
            Removal(start: 4, end: 5, reason: .repair, text: "就是"),
            Removal(start: 6, end: 7, reason: .longPause, text: "")
        ]

        let result = AnalysisResult(removals: removals, originalDuration: 60)

        #expect(result.statistics[.filler] == 2)
        #expect(result.statistics[.repair] == 1)
        #expect(result.statistics[.longPause] == 1)
        #expect(result.statistics[.restart] == nil)
        #expect(result.statistics[.mouthNoise] == nil)
    }

    @Test("AnalysisResult removed duration")
    func testAnalysisResultRemovedDuration() {
        let removals = [
            Removal(start: 0, end: 2, reason: .filler, text: "嗯"),
            Removal(start: 5, end: 8, reason: .repair, text: "就是")
        ]

        let result = AnalysisResult(removals: removals, originalDuration: 60)

        #expect(result.removedDuration == 5.0) // 2 + 3
    }

    @Test("AnalysisResult empty removals")
    func testAnalysisResultEmpty() {
        let result = AnalysisResult(removals: [], originalDuration: 60)

        #expect(result.removedDuration == 0)
        #expect(result.statistics.isEmpty)
    }
}

/// EditReport 測試
@Suite("EditReport Tests")
struct EditReportTests {

    @Test("EditReport calculations")
    func testEditReportCalculations() {
        let edits = [
            AppliedEdit(originalStart: 5, originalEnd: 7, reason: .filler, text: "嗯"),
            AppliedEdit(originalStart: 10, originalEnd: 12, reason: .repair, text: "就是說")
        ]

        let report = EditReport(
            inputURL: URL(fileURLWithPath: "/input.wav"),
            outputURL: URL(fileURLWithPath: "/output.wav"),
            originalDuration: 60,
            editedDuration: 56,
            edits: edits
        )

        #expect(report.removedDuration == 4.0)
        #expect(report.reductionPercent == (4.0 / 60.0) * 100)
        #expect(report.edits.count == 2)
    }

    @Test("EditReport zero reduction")
    func testEditReportZeroReduction() {
        let report = EditReport(
            inputURL: URL(fileURLWithPath: "/input.wav"),
            outputURL: URL(fileURLWithPath: "/output.wav"),
            originalDuration: 60,
            editedDuration: 60,
            edits: []
        )

        #expect(report.removedDuration == 0)
        #expect(report.reductionPercent == 0)
    }
}

/// WaveformGenerator Resolution 測試
@Suite("WaveformGenerator Resolution Tests")
struct WaveformResolutionTests {

    @Test("Resolution raw values")
    func testResolutionRawValues() {
        #expect(WaveformGenerator.Resolution.thumbnail.rawValue == 200)
        #expect(WaveformGenerator.Resolution.preview.rawValue == 1000)
        #expect(WaveformGenerator.Resolution.standard.rawValue == 5000)
        #expect(WaveformGenerator.Resolution.detailed.rawValue == 20000)
        #expect(WaveformGenerator.Resolution.full.rawValue == 0)
    }

    @Test("Resolution samples per second")
    func testResolutionSamplesPerSecond() {
        #expect(WaveformGenerator.Resolution.thumbnail.samplesPerSecond == 2)
        #expect(WaveformGenerator.Resolution.preview.samplesPerSecond == 10)
        #expect(WaveformGenerator.Resolution.standard.samplesPerSecond == 50)
        #expect(WaveformGenerator.Resolution.detailed.samplesPerSecond == 200)
        #expect(WaveformGenerator.Resolution.full.samplesPerSecond == 100)
    }
}

/// WaveformData 測試
@Suite("WaveformData Tests")
struct WaveformDataTests {

    @Test("WaveformData initialization")
    func testWaveformDataInit() {
        let peaks: [Float] = [0.1, 0.5, 0.3, 0.8, 0.2]
        let data = WaveformGenerator.WaveformData(
            peaks: peaks,
            secondsPerSample: 0.1,
            duration: 0.5,
            resolution: .preview
        )

        #expect(data.peaks.count == 5)
        #expect(data.secondsPerSample == 0.1)
        #expect(data.duration == 0.5)
        #expect(data.resolution == .preview)
    }

    @Test("WaveformData peaks extraction")
    func testWaveformDataPeaksExtraction() {
        let peaks: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        let data = WaveformGenerator.WaveformData(
            peaks: peaks,
            secondsPerSample: 1.0,
            duration: 10.0,
            resolution: .standard
        )

        let extracted = data.peaks(from: 2.0, to: 5.0)
        #expect(extracted.count == 3)
        #expect(extracted.first == 0.3)
    }

    @Test("WaveformData downsampling")
    func testWaveformDataDownsampling() {
        let peaks: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        let data = WaveformGenerator.WaveformData(
            peaks: peaks,
            secondsPerSample: 0.1,
            duration: 1.0,
            resolution: .standard
        )

        let downsampled = data.downsampled(to: 5)
        #expect(downsampled.count == 5)
        #expect(downsampled[0] == 0.2) // max of [0.1, 0.2]
        #expect(downsampled[4] == 1.0) // max of [0.9, 1.0]
    }

    @Test("WaveformData downsampling returns original when target is larger")
    func testWaveformDataDownsamplingLargerTarget() {
        let peaks: [Float] = [0.1, 0.5, 0.3]
        let data = WaveformGenerator.WaveformData(
            peaks: peaks,
            secondsPerSample: 0.1,
            duration: 0.3,
            resolution: .thumbnail
        )

        let downsampled = data.downsampled(to: 10)
        #expect(downsampled == peaks)
    }
}

/// WaveformError 測試
@Suite("WaveformError Tests")
struct WaveformErrorTests {

    @Test("WaveformError descriptions")
    func testWaveformErrorDescriptions() {
        let invalidAudio = WaveformError.invalidAudio
        #expect(invalidAudio.errorDescription == "無效的音訊檔案")

        let noAudioTrack = WaveformError.noAudioTrack
        #expect(noAudioTrack.errorDescription == "找不到音訊軌道")

        let readFailed = WaveformError.readFailed("測試錯誤")
        #expect(readFailed.errorDescription == "讀取失敗: 測試錯誤")
    }
}
