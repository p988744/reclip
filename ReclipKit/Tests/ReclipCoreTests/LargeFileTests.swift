import Testing
import Foundation
@testable import ReclipCore

/// Thread-safe counter for progress tracking
final class Counter: @unchecked Sendable {
    private var _value: Int = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}

/// 大型檔案測試
@Suite("Large File Tests")
struct LargeFileTests {

    static let testFileURL = URL(fileURLWithPath: "/Users/weifan/Library/CloudStorage/SynologyDrive-macbook/pycon/S5/S5EP2.mp3")

    @Test("Generate thumbnail waveform from large MP3")
    func testGenerateThumbnailWaveform() async throws {
        // 檢查檔案是否存在
        guard FileManager.default.fileExists(atPath: Self.testFileURL.path) else {
            Issue.record("測試檔案不存在: \(Self.testFileURL.path)")
            return
        }

        // 生成縮圖波形（應該很快）
        let startTime = Date()
        let waveform = try await WaveformGenerator.generateThumbnail(from: Self.testFileURL)
        let elapsed = Date().timeIntervalSince(startTime)

        // 驗證結果
        #expect(waveform.peaks.count > 0)
        #expect(waveform.duration > 0)
        #expect(waveform.resolution == .thumbnail)

        // 大型檔案（87分鐘）可能需要較長時間，應該在 60 秒內完成
        #expect(elapsed < 60.0, "縮圖生成時間: \(elapsed)s")

        print("✅ 縮圖波形生成成功")
        print("   - 樣本數: \(waveform.peaks.count)")
        print("   - 時長: \(waveform.duration)s")
        print("   - 耗時: \(String(format: "%.2f", elapsed))s")
    }

    @Test("Generate preview waveform from large MP3")
    func testGeneratePreviewWaveform() async throws {
        guard FileManager.default.fileExists(atPath: Self.testFileURL.path) else {
            Issue.record("測試檔案不存在")
            return
        }

        let startTime = Date()
        let waveform = try await WaveformGenerator.generatePreview(from: Self.testFileURL)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(waveform.peaks.count > 0)
        #expect(waveform.duration > 0)
        #expect(waveform.resolution == .preview)

        print("✅ 預覽波形生成成功")
        print("   - 樣本數: \(waveform.peaks.count)")
        print("   - 時長: \(waveform.duration)s")
        print("   - 耗時: \(String(format: "%.2f", elapsed))s")
    }

    @Test("Generate standard waveform from large MP3")
    func testGenerateStandardWaveform() async throws {
        guard FileManager.default.fileExists(atPath: Self.testFileURL.path) else {
            Issue.record("測試檔案不存在")
            return
        }

        let progressCounter = Counter()

        let startTime = Date()
        let waveform = try await WaveformGenerator.generate(
            from: Self.testFileURL,
            resolution: .standard,
            useCache: false
        ) { _ in
            progressCounter.increment()
        }
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(waveform.peaks.count > 0)
        #expect(waveform.duration > 0)
        #expect(waveform.resolution == .standard)
        #expect(progressCounter.value > 0)

        print("✅ 標準波形生成成功")
        print("   - 樣本數: \(waveform.peaks.count)")
        print("   - 時長: \(waveform.duration)s")
        print("   - 耗時: \(String(format: "%.2f", elapsed))s")
        print("   - 進度回調次數: \(progressCounter.value)")
    }

    @Test("Get audio info from large MP3")
    func testGetAudioInfo() async throws {
        guard FileManager.default.fileExists(atPath: Self.testFileURL.path) else {
            Issue.record("測試檔案不存在")
            return
        }

        let editor = AudioEditor()
        let info = try await editor.getAudioInfo(url: Self.testFileURL)

        #expect(info.duration > 0)
        #expect(info.sampleRate > 0)
        #expect(info.channelCount > 0)

        print("✅ 音訊資訊取得成功")
        print("   - 時長: \(info.duration)s (\(info.duration / 60)分鐘)")
        print("   - 取樣率: \(info.sampleRate) Hz")
        print("   - 聲道數: \(info.channelCount)")
    }

    @Test("Waveform downsampling performance")
    func testWaveformDownsampling() async throws {
        guard FileManager.default.fileExists(atPath: Self.testFileURL.path) else {
            Issue.record("測試檔案不存在")
            return
        }

        // 生成詳細波形
        let waveform = try await WaveformGenerator.generate(
            from: Self.testFileURL,
            resolution: .detailed,
            useCache: true
        )

        // 測試降採樣效能
        let targetCounts = [100, 500, 1000, 2000]

        for targetCount in targetCounts {
            let startTime = Date()
            let downsampled = waveform.downsampled(to: targetCount)
            let elapsed = Date().timeIntervalSince(startTime)

            #expect(downsampled.count == targetCount)
            #expect(elapsed < 0.1, "降採樣到 \(targetCount) 個點耗時過長: \(elapsed)s")
        }

        print("✅ 波形降採樣效能測試通過")
    }

    @Test("Peaks extraction by time range")
    func testPeaksExtraction() async throws {
        guard FileManager.default.fileExists(atPath: Self.testFileURL.path) else {
            Issue.record("測試檔案不存在")
            return
        }

        let waveform = try await WaveformGenerator.generatePreview(from: Self.testFileURL)

        // 取得前 10 秒的 peaks
        let peaks = waveform.peaks(from: 0, to: 10)

        #expect(peaks.count > 0)
        #expect(peaks.count <= waveform.peaks.count)

        print("✅ 波形片段取得成功")
        print("   - 全部樣本數: \(waveform.peaks.count)")
        print("   - 0-10秒樣本數: \(peaks.count)")
    }
}
