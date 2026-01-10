import Foundation
import AVFoundation
import ReclipCore
import WhisperKit

/// WhisperKit 本地 ASR 提供者
public final class WhisperKitProvider: ASRProvider, @unchecked Sendable {
    public let name = "WhisperKit"
    public let isLocal = true

    public var supportedLanguages: [String] {
        // WhisperKit 支援多語言
        ["zh", "en", "ja", "ko", "es", "fr", "de", "it", "pt", "ru", "ar", "hi"]
    }

    private var whisperKit: WhisperKit?
    private let modelName: String
    private let computeOptions: ModelComputeOptions

    /// 大檔案分段處理的閾值（500MB）
    private let largeFileThreshold: UInt64 = 500 * 1024 * 1024

    /// 每段處理的最大長度（秒）- 用於大檔案
    private let chunkDuration: TimeInterval = 600 // 10 分鐘

    public init(
        modelName: String = "large-v3",
        computeOptions: ModelComputeOptions = .init()
    ) {
        self.modelName = modelName
        self.computeOptions = computeOptions
    }

    /// 載入模型
    public func loadModel() async throws {
        whisperKit = try await WhisperKit(
            model: modelName,
            computeOptions: computeOptions
        )
    }

    /// 卸載模型（釋放記憶體）
    public func unloadModel() {
        whisperKit = nil
    }

    public func transcribe(
        url: URL,
        language: String,
        includeWordTimestamps: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptResult {
        guard whisperKit != nil else {
            throw ASRError.modelNotLoaded
        }

        guard supportedLanguages.contains(language) else {
            throw ASRError.unsupportedLanguage(language)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ASRError.fileNotFound(url)
        }

        // 檢查檔案大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0

        if fileSize > largeFileThreshold {
            // 大檔案：使用分段處理
            return try await transcribeLargeFile(
                url: url,
                language: language,
                includeWordTimestamps: includeWordTimestamps,
                progress: progress
            )
        } else {
            // 一般檔案：直接處理
            return try await transcribeDirectly(
                url: url,
                language: language,
                includeWordTimestamps: includeWordTimestamps,
                progress: progress
            )
        }
    }

    /// 直接轉錄（適用於一般大小檔案）
    private func transcribeDirectly(
        url: URL,
        language: String,
        includeWordTimestamps: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptResult {
        guard let whisperKit else {
            throw ASRError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: language,
            wordTimestamps: includeWordTimestamps
        )

        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: options
        ) { progressInfo in
            let fractionComplete = progressInfo.timings.decodingLoop / max(1.0, progressInfo.timings.fullPipeline)
            progress(min(1.0, fractionComplete))
            return nil
        }

        return convertResults(results, language: language)
    }

    /// 分段轉錄（適用於大型檔案 >500MB）
    private func transcribeLargeFile(
        url: URL,
        language: String,
        includeWordTimestamps: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscriptResult {
        guard let whisperKit else {
            throw ASRError.modelNotLoaded
        }

        // 取得音訊長度
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        // 計算分段數量
        let numberOfChunks = Int(ceil(duration / chunkDuration))

        var allSegments: [Segment] = []
        var processedChunks = 0

        // 分段處理
        for chunkIndex in 0..<numberOfChunks {
            let startTime = Double(chunkIndex) * chunkDuration
            let endTime = min(startTime + chunkDuration, duration)

            let options = DecodingOptions(
                language: language,
                wordTimestamps: includeWordTimestamps,
                clipTimestamps: [Float(startTime)]  // 指定開始時間
            )

            // 轉錄這一段
            let results = try await whisperKit.transcribe(
                audioPath: url.path,
                decodeOptions: options
            ) { progressInfo in
                // 計算整體進度
                let chunkProgress = progressInfo.timings.decodingLoop / max(1.0, progressInfo.timings.fullPipeline)
                let overallProgress = (Double(processedChunks) + chunkProgress) / Double(numberOfChunks)
                progress(min(1.0, overallProgress))
                return nil
            }

            // 轉換並調整時間戳記
            let chunkResult = convertResults(results, language: language)

            // 過濾超出範圍的 segments（clipTimestamps 可能有重疊）
            let filteredSegments = chunkResult.segments.filter { segment in
                segment.start >= startTime && segment.start < endTime
            }

            allSegments.append(contentsOf: filteredSegments)

            processedChunks += 1
            progress(Double(processedChunks) / Double(numberOfChunks))
        }

        // 按時間排序並移除重複
        let sortedSegments = allSegments.sorted { $0.start < $1.start }

        return TranscriptResult(
            segments: sortedSegments,
            language: language,
            duration: duration
        )
    }

    private func convertResults(
        _ results: [TranscriptionResult],
        language: String
    ) -> TranscriptResult {
        var segments: [Segment] = []
        var totalDuration: TimeInterval = 0

        for result in results {
            for segment in result.segments {
                let words: [WordSegment] = (segment.words ?? []).map { word in
                    WordSegment(
                        word: word.word,
                        start: TimeInterval(word.start),
                        end: TimeInterval(word.end),
                        confidence: Double(word.probability),
                        speaker: nil
                    )
                }

                let seg = Segment(
                    text: segment.text.trimmingCharacters(in: .whitespaces),
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    speaker: nil,
                    words: words
                )

                segments.append(seg)
                totalDuration = max(totalDuration, TimeInterval(segment.end))
            }
        }

        return TranscriptResult(
            segments: segments,
            language: language,
            duration: totalDuration
        )
    }
}
