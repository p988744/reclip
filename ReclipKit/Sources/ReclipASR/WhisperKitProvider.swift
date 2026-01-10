import Foundation
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
        guard let whisperKit else {
            throw ASRError.modelNotLoaded
        }

        guard supportedLanguages.contains(language) else {
            throw ASRError.unsupportedLanguage(language)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ASRError.fileNotFound(url)
        }

        // 配置轉錄選項
        let options = DecodingOptions(
            language: language,
            wordTimestamps: includeWordTimestamps
        )

        // 執行轉錄
        let results = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: options
        ) { progressInfo in
            // 回報進度（使用 fractionComplete 如果可用）
            let fractionComplete = progressInfo.timings.decodingLoop / max(1.0, progressInfo.timings.fullPipeline)
            progress(min(1.0, fractionComplete))
            return nil // 繼續處理
        }

        // 轉換結果
        return convertResults(results, language: language)
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
