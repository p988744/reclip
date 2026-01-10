import Foundation
import AVFoundation
import Accelerate

/// 波形生成器 - 支援 proxy 模式
public actor WaveformGenerator {

    /// 波形精度等級
    public enum Resolution: Int, Sendable {
        case thumbnail = 200     // 縮圖：200 個採樣點（極速，<100ms）
        case preview = 1000      // 預覽：1000 個採樣點（快速）
        case standard = 5000     // 標準：5000 個採樣點
        case detailed = 20000    // 詳細：20000 個採樣點
        case full = 0            // 完整：每秒 100 個採樣點

        var samplesPerSecond: Int {
            switch self {
            case .thumbnail: return 2
            case .preview: return 10
            case .standard: return 50
            case .detailed: return 200
            case .full: return 100
            }
        }

        /// 預估記憶體用量 (bytes)
        var estimatedMemory: Int {
            rawValue * MemoryLayout<Float>.size
        }
    }

    /// 波形資料
    public struct WaveformData: Sendable {
        /// Peak 值陣列（正值）
        public let peaks: [Float]
        /// 每個 peak 對應的時間長度（秒）
        public let secondsPerSample: Double
        /// 音訊總長度
        public let duration: TimeInterval
        /// 精度等級
        public let resolution: Resolution

        public init(peaks: [Float], secondsPerSample: Double, duration: TimeInterval, resolution: Resolution) {
            self.peaks = peaks
            self.secondsPerSample = secondsPerSample
            self.duration = duration
            self.resolution = resolution
        }
    }

    // MARK: - Cache

    /// 波形快取目錄
    private static var cacheDirectory: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let waveformDir = cacheDir.appendingPathComponent("Reclip/Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: waveformDir, withIntermediateDirectories: true)
        return waveformDir
    }

    /// 取得快取檔案路徑
    private static func cacheURL(for audioURL: URL, resolution: Resolution) -> URL {
        let hash = audioURL.absoluteString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(32)
        return cacheDirectory.appendingPathComponent("\(hash)_\(resolution.rawValue).waveform")
    }

    // MARK: - Generation

    /// 生成波形（支援快取）
    public static func generate(
        from url: URL,
        resolution: Resolution = .standard,
        useCache: Bool = true,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> WaveformData {
        // 檢查快取
        let cacheURL = cacheURL(for: url, resolution: resolution)
        if useCache, let cached = loadFromCache(cacheURL) {
            return cached
        }

        // 生成波形
        let waveform = try await generateWaveform(from: url, resolution: resolution, progress: progress)

        // 儲存快取
        if useCache {
            saveToCache(waveform, at: cacheURL)
        }

        return waveform
    }

    /// 快速預覽波形（最低精度）
    public static func generatePreview(from url: URL) async throws -> WaveformData {
        try await generate(from: url, resolution: .preview, useCache: true, progress: nil)
    }

    /// 極速縮圖波形（串流模式，記憶體用量極低）
    /// 適用於 1-2GB 大型檔案的快速預覽
    public static func generateThumbnail(from url: URL) async throws -> WaveformData {
        // 檢查快取
        let cacheURL = cacheURL(for: url, resolution: .thumbnail)
        if let cached = loadFromCache(cacheURL) {
            return cached
        }

        // 串流生成 - 不載入完整音訊到記憶體
        let waveform = try await generateStreamingThumbnail(from: url)

        // 儲存快取
        saveToCache(waveform, at: cacheURL)

        return waveform
    }

    /// 串流生成縮圖（記憶體友善）
    private static func generateStreamingThumbnail(from url: URL) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard duration > 0 else {
            throw WaveformError.invalidAudio
        }

        let targetSamples = Resolution.thumbnail.rawValue
        let secondsPerSample = duration / Double(targetSamples)

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)

        // 使用較低採樣率進一步減少資料量
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8000,  // 極低採樣率
            AVNumberOfChannelsKey: 1
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        // 串流計算 peaks - 不儲存所有 samples
        let totalSamples = Int(duration * 8000)
        let samplesPerPeak = max(1, totalSamples / targetSamples)

        var peaks: [Float] = Array(repeating: 0, count: targetSamples)
        var currentPeakIndex = 0
        var samplesInCurrentPeak = 0
        var currentMax: Int16 = 0

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let dataPointer {
                let samples = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: length / 2)
                let sampleCount = length / 2

                for i in 0..<sampleCount {
                    let absVal = abs(samples[i])
                    if absVal > currentMax {
                        currentMax = absVal
                    }

                    samplesInCurrentPeak += 1

                    if samplesInCurrentPeak >= samplesPerPeak {
                        if currentPeakIndex < targetSamples {
                            peaks[currentPeakIndex] = Float(currentMax) / Float(Int16.max)
                        }
                        currentPeakIndex += 1
                        samplesInCurrentPeak = 0
                        currentMax = 0
                    }
                }
            }
        }

        // 處理最後一個 peak
        if samplesInCurrentPeak > 0 && currentPeakIndex < targetSamples {
            peaks[currentPeakIndex] = Float(currentMax) / Float(Int16.max)
        }

        return WaveformData(
            peaks: peaks,
            secondsPerSample: secondsPerSample,
            duration: duration,
            resolution: .thumbnail
        )
    }

    // MARK: - Private Methods

    private static func generateWaveform(
        from url: URL,
        resolution: Resolution,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> WaveformData {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard duration > 0 else {
            throw WaveformError.invalidAudio
        }

        // 計算目標採樣數
        let targetSamples: Int
        if resolution == .full {
            targetSamples = Int(duration * Double(resolution.samplesPerSecond))
        } else {
            targetSamples = resolution.rawValue
        }

        let secondsPerSample = duration / Double(targetSamples)

        // 讀取音訊
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,  // 降採樣到 16kHz
            AVNumberOfChannelsKey: 1  // 單聲道
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        // 收集所有 peak 值
        var allSamples: [Int16] = []
        allSamples.reserveCapacity(Int(duration * 16000))

        while let buffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let dataPointer {
                let samples = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: length / 2)
                let sampleCount = length / 2
                allSamples.append(contentsOf: UnsafeBufferPointer(start: samples, count: sampleCount))
            }

            // 回報進度
            if let progress {
                let currentDuration = Double(allSamples.count) / 16000.0
                progress(min(currentDuration / duration, 0.99))
            }
        }

        // 計算 peaks
        let samplesPerPeak = max(1, allSamples.count / targetSamples)
        var peaks: [Float] = []
        peaks.reserveCapacity(targetSamples)

        for i in stride(from: 0, to: allSamples.count, by: samplesPerPeak) {
            let end = min(i + samplesPerPeak, allSamples.count)
            let chunk = Array(allSamples[i..<end])

            // 找出這個區段的最大絕對值
            var maxVal: Int16 = 0
            for sample in chunk {
                let absVal = abs(sample)
                if absVal > maxVal {
                    maxVal = absVal
                }
            }

            // 正規化到 0-1
            peaks.append(Float(maxVal) / Float(Int16.max))
        }

        progress?(1.0)

        return WaveformData(
            peaks: peaks,
            secondsPerSample: secondsPerSample,
            duration: duration,
            resolution: resolution
        )
    }

    // MARK: - Cache I/O

    private static func loadFromCache(_ url: URL) -> WaveformData? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CachedWaveform.self, from: data) else {
            return nil
        }
        return decoded.toWaveformData()
    }

    private static func saveToCache(_ waveform: WaveformData, at url: URL) {
        let cached = CachedWaveform(from: waveform)
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Cache Model

private struct CachedWaveform: Codable {
    let peaks: [Float]
    let secondsPerSample: Double
    let duration: TimeInterval
    let resolution: Int

    init(from waveform: WaveformGenerator.WaveformData) {
        self.peaks = waveform.peaks
        self.secondsPerSample = waveform.secondsPerSample
        self.duration = waveform.duration
        self.resolution = waveform.resolution.rawValue
    }

    func toWaveformData() -> WaveformGenerator.WaveformData {
        WaveformGenerator.WaveformData(
            peaks: peaks,
            secondsPerSample: secondsPerSample,
            duration: duration,
            resolution: WaveformGenerator.Resolution(rawValue: resolution) ?? .standard
        )
    }
}

// MARK: - Errors

public enum WaveformError: LocalizedError {
    case invalidAudio
    case noAudioTrack
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAudio:
            return "無效的音訊檔案"
        case .noAudioTrack:
            return "找不到音訊軌道"
        case .readFailed(let message):
            return "讀取失敗: \(message)"
        }
    }
}

// MARK: - Convenience Extensions

extension WaveformGenerator.WaveformData {
    /// 取得指定時間範圍內的 peaks
    public func peaks(from startTime: TimeInterval, to endTime: TimeInterval) -> ArraySlice<Float> {
        let startIndex = max(0, Int(startTime / secondsPerSample))
        let endIndex = min(peaks.count, Int(endTime / secondsPerSample))
        return peaks[startIndex..<endIndex]
    }

    /// 取得降採樣後的 peaks（用於縮放顯示）
    public func downsampled(to targetCount: Int) -> [Float] {
        guard targetCount > 0, peaks.count > targetCount else {
            return peaks
        }

        let ratio = peaks.count / targetCount
        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let start = i * ratio
            let end = min(start + ratio, peaks.count)
            let chunk = peaks[start..<end]
            result.append(chunk.max() ?? 0)
        }

        return result
    }
}
