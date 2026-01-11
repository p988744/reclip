import Foundation
import AVFoundation

/// 多層級波形快取 - 類似 Audacity 的 Waveform Pyramid
/// 支援大型音訊檔案的高效能顯示
public actor WaveformCache {

    // MARK: - Types

    /// 快取層級（每層解析度減半）
    public enum Level: Int, CaseIterable, Sendable {
        case level0 = 0   // 1:1 - 每秒 1000 samples（最細）
        case level1 = 1   // 1:4 - 每秒 250 samples
        case level2 = 2   // 1:16 - 每秒 62 samples
        case level3 = 3   // 1:64 - 每秒 16 samples
        case level4 = 4   // 1:256 - 每秒 4 samples（最粗）

        var samplesPerSecond: Int {
            1000 / (1 << rawValue)
        }

        var blockSize: Int {
            // 每個區塊包含的秒數
            switch self {
            case .level0: return 10    // 10秒/區塊
            case .level1: return 30    // 30秒/區塊
            case .level2: return 60    // 1分鐘/區塊
            case .level3: return 300   // 5分鐘/區塊
            case .level4: return 600   // 10分鐘/區塊
            }
        }

        /// 根據縮放程度選擇適當層級
        static func forZoom(pixelsPerSecond: Double) -> Level {
            // 選擇能提供足夠解析度的最粗層級
            for level in Level.allCases.reversed() {
                if Double(level.samplesPerSecond) >= pixelsPerSecond * 0.5 {
                    return level
                }
            }
            return .level0
        }
    }

    /// 區塊資料（使用 Int16 節省記憶體）
    public struct Block: Sendable {
        let level: Level
        let index: Int           // 區塊索引
        let startTime: Double
        let endTime: Double
        let peaksInt16: [Int16]  // Peak 值（Int16 節省 50% 記憶體）

        /// 轉換為 Float 陣列（用於繪圖）
        var peaks: [Float] {
            peaksInt16.map { Float($0) / Float(Int16.max) }
        }

        /// 取得指定範圍的 Float peaks
        func peaks(range: Range<Int>) -> [Float] {
            let clampedRange = range.clamped(to: 0..<peaksInt16.count)
            return peaksInt16[clampedRange].map { Float($0) / Float(Int16.max) }
        }
    }

    /// 快取資訊
    public struct CacheInfo: Sendable {
        let audioURL: URL
        let duration: TimeInterval
        let blocksByLevel: [Level: Int]  // 每層的區塊數
        var loadedBlocks: Set<String>    // 已載入的區塊 ID
    }

    // MARK: - Properties

    private var cacheInfo: CacheInfo?
    private var blocks: [String: Block] = [:]  // key: "level_index"
    private let maxCachedBlocks = 50           // 最大快取區塊數

    private var audioURL: URL?
    private var audioAsset: AVURLAsset?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// 初始化快取（快速，只讀取 metadata）
    public func initialize(url: URL) async throws -> CacheInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        self.audioURL = url
        self.audioAsset = asset

        var blocksByLevel: [Level: Int] = [:]
        for level in Level.allCases {
            blocksByLevel[level] = Int(ceil(duration / Double(level.blockSize)))
        }

        let info = CacheInfo(
            audioURL: url,
            duration: duration,
            blocksByLevel: blocksByLevel,
            loadedBlocks: []
        )

        self.cacheInfo = info
        return info
    }

    /// 取得指定時間範圍和縮放程度的波形資料
    /// - Parameters:
    ///   - startTime: 開始時間
    ///   - endTime: 結束時間
    ///   - pixelsPerSecond: 每秒像素數（決定解析度）
    /// - Returns: Peak 值陣列
    public func getWaveform(
        startTime: Double,
        endTime: Double,
        pixelsPerSecond: Double
    ) async throws -> [Float] {
        guard let info = cacheInfo else {
            throw WaveformCacheError.notInitialized
        }

        let level = Level.forZoom(pixelsPerSecond: pixelsPerSecond)

        // 計算需要的區塊
        let blockSize = Double(level.blockSize)
        let startBlock = Int(floor(startTime / blockSize))
        let endBlock = Int(ceil(endTime / blockSize))

        // 載入所需區塊
        var allPeaks: [Float] = []

        for blockIndex in startBlock...endBlock {
            let block = try await loadBlock(level: level, index: blockIndex)

            // 計算這個區塊中需要的範圍
            let blockStartTime = Double(blockIndex) * blockSize
            let blockEndTime = blockStartTime + blockSize

            let rangeStart = max(startTime, blockStartTime)
            let rangeEnd = min(endTime, blockEndTime)

            // 轉換為 samples 索引
            let samplesPerSecond = Double(level.samplesPerSecond)
            let localStartIndex = Int((rangeStart - blockStartTime) * samplesPerSecond)
            let localEndIndex = Int((rangeEnd - blockStartTime) * samplesPerSecond)

            let clampedStart = max(0, min(localStartIndex, block.peaks.count))
            let clampedEnd = max(clampedStart, min(localEndIndex, block.peaks.count))

            allPeaks.append(contentsOf: block.peaks[clampedStart..<clampedEnd])
        }

        return allPeaks
    }

    /// 預載指定範圍的區塊（背景執行）
    public func preload(
        startTime: Double,
        endTime: Double,
        level: Level
    ) async {
        let blockSize = Double(level.blockSize)
        let startBlock = Int(floor(startTime / blockSize))
        let endBlock = Int(ceil(endTime / blockSize))

        for blockIndex in startBlock...endBlock {
            let key = blockKey(level: level, index: blockIndex)
            if blocks[key] == nil {
                _ = try? await loadBlock(level: level, index: blockIndex)
            }
        }
    }

    /// 清除快取
    public func clearCache() {
        blocks.removeAll()
    }

    // MARK: - Private Methods

    private func blockKey(level: Level, index: Int) -> String {
        "\(level.rawValue)_\(index)"
    }

    private func loadBlock(level: Level, index: Int) async throws -> Block {
        let key = blockKey(level: level, index: index)

        // 檢查快取
        if let cached = blocks[key] {
            return cached
        }

        // 生成區塊
        let block = try await generateBlock(level: level, index: index)

        // 加入快取（淘汰舊區塊）
        if blocks.count >= maxCachedBlocks {
            evictOldestBlocks()
        }
        blocks[key] = block

        return block
    }

    private func generateBlock(level: Level, index: Int) async throws -> Block {
        guard let asset = audioAsset else {
            throw WaveformCacheError.notInitialized
        }

        let blockSize = Double(level.blockSize)
        let startTime = Double(index) * blockSize
        let endTime = min(startTime + blockSize, cacheInfo?.duration ?? 0)

        guard endTime > startTime else {
            // 空區塊
            return Block(
                level: level,
                index: index,
                startTime: startTime,
                endTime: endTime,
                peaksInt16: []
            )
        }

        let samplesPerSecond = level.samplesPerSecond
        let targetSamples = Int((endTime - startTime) * Double(samplesPerSecond))

        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformCacheError.noAudioTrack
        }

        // 設定讀取範圍
        let reader = try AVAssetReader(asset: asset)

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 44100),
            end: CMTime(seconds: endTime, preferredTimescale: 44100)
        )
        reader.timeRange = timeRange

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformCacheError.readFailed
        }

        // 串流計算 peaks（直接存為 Int16 節省記憶體）
        let totalExpectedSamples = Int((endTime - startTime) * 16000)
        let samplesPerPeak = max(1, totalExpectedSamples / targetSamples)

        var peaksInt16: [Int16] = []
        peaksInt16.reserveCapacity(targetSamples)

        var currentMax: Int16 = 0
        var samplesInPeak = 0

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

                    samplesInPeak += 1
                    if samplesInPeak >= samplesPerPeak {
                        peaksInt16.append(currentMax)  // 直接存 Int16
                        currentMax = 0
                        samplesInPeak = 0
                    }
                }
            }
        }

        // 最後一個 peak
        if samplesInPeak > 0 {
            peaksInt16.append(currentMax)
        }

        return Block(
            level: level,
            index: index,
            startTime: startTime,
            endTime: endTime,
            peaksInt16: peaksInt16
        )
    }

    private func evictOldestBlocks() {
        // 簡單策略：移除一半的區塊
        let keysToRemove = Array(blocks.keys.prefix(blocks.count / 2))
        for key in keysToRemove {
            blocks.removeValue(forKey: key)
        }
    }
}

// MARK: - Errors

public enum WaveformCacheError: LocalizedError {
    case notInitialized
    case noAudioTrack
    case readFailed

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "波形快取尚未初始化"
        case .noAudioTrack:
            return "找不到音訊軌道"
        case .readFailed:
            return "讀取音訊失敗"
        }
    }
}
