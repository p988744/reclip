import Foundation
import AVFoundation

/// 音訊編輯器
public actor AudioEditor {
    /// 編輯器配置
    public struct Configuration: Sendable {
        /// Crossfade 長度（秒）
        public let crossfadeDuration: TimeInterval
        /// 最小移除長度（秒）
        public let minRemovalDuration: TimeInterval
        /// 合併相鄰區間的閾值（秒）
        public let mergeGap: TimeInterval
        /// 零交叉點搜尋範圍（秒）
        public let zeroCrossingSearchRange: TimeInterval

        public init(
            crossfadeDuration: TimeInterval = 0.03,
            minRemovalDuration: TimeInterval = 0.1,
            mergeGap: TimeInterval = 0.05,
            zeroCrossingSearchRange: TimeInterval = 0.005
        ) {
            self.crossfadeDuration = crossfadeDuration
            self.minRemovalDuration = minRemovalDuration
            self.mergeGap = mergeGap
            self.zeroCrossingSearchRange = zeroCrossingSearchRange
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// 取得音訊資訊
    public func getAudioInfo(url: URL) async throws -> AudioInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)

        guard let track = tracks.first else {
            throw AudioEditorError.noAudioTrack
        }

        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw AudioEditorError.invalidFormat
        }

        let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        let sampleRate = audioStreamBasicDescription?.pointee.mSampleRate ?? 44100
        let channelCount = Int(audioStreamBasicDescription?.pointee.mChannelsPerFrame ?? 1)

        return AudioInfo(
            url: url,
            duration: duration.seconds,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    /// 執行剪輯
    public func edit(
        inputURL: URL,
        outputURL: URL,
        analysis: AnalysisResult,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> EditReport {
        let audioInfo = try await getAudioInfo(url: inputURL)

        // 過濾太短的移除區間
        let validRemovals = analysis.removals.filter {
            $0.duration >= configuration.minRemovalDuration
        }

        // 合併相鄰區間
        let mergedRemovals = mergeRemovals(validRemovals)

        // 排序
        let sortedRemovals = mergedRemovals.sorted { $0.start < $1.start }

        // 計算保留區間
        let keepRegions = computeKeepRegions(
            removals: sortedRemovals,
            totalDuration: audioInfo.duration
        )

        // 建立 composition
        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioEditorError.compositionFailed
        }

        let asset = AVURLAsset(url: inputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let sourceTrack = audioTracks.first else {
            throw AudioEditorError.noAudioTrack
        }

        // 插入保留區間
        var insertTime = CMTime.zero
        let totalRegions = keepRegions.count

        for (index, region) in keepRegions.enumerated() {
            let startTime = CMTime(seconds: region.start, preferredTimescale: 44100)
            let endTime = CMTime(seconds: region.end, preferredTimescale: 44100)
            let timeRange = CMTimeRange(start: startTime, end: endTime)

            try compositionTrack.insertTimeRange(
                timeRange,
                of: sourceTrack,
                at: insertTime
            )

            insertTime = CMTimeAdd(insertTime, timeRange.duration)

            // 回報進度
            progress(Double(index + 1) / Double(totalRegions))
        }

        // 建立音訊 mix（用於 crossfade）
        let audioMix = createAudioMix(
            for: compositionTrack,
            keepRegions: keepRegions
        )

        // 匯出
        try await exportComposition(
            composition: composition,
            audioMix: audioMix,
            to: outputURL
        )

        // 取得輸出資訊
        let outputInfo = try await getAudioInfo(url: outputURL)

        // 建立報告
        let appliedEdits = sortedRemovals.map { removal in
            AppliedEdit(
                originalStart: removal.start,
                originalEnd: removal.end,
                reason: removal.reason,
                text: removal.text
            )
        }

        return EditReport(
            inputURL: inputURL,
            outputURL: outputURL,
            originalDuration: audioInfo.duration,
            editedDuration: outputInfo.duration,
            edits: appliedEdits
        )
    }

    /// 合併相鄰的移除區間
    private func mergeRemovals(_ removals: [Removal]) -> [Removal] {
        guard !removals.isEmpty else { return [] }

        let sorted = removals.sorted { $0.start < $1.start }
        var merged: [Removal] = [sorted[0]]

        for removal in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            let gap = removal.start - last.end

            if gap <= configuration.mergeGap {
                // 合併
                merged[merged.count - 1] = Removal(
                    id: last.id,
                    start: last.start,
                    end: removal.end,
                    reason: last.reason,
                    text: "\(last.text) ... \(removal.text)",
                    confidence: min(last.confidence, removal.confidence)
                )
            } else {
                merged.append(removal)
            }
        }

        return merged
    }

    /// 計算保留區間
    private func computeKeepRegions(
        removals: [Removal],
        totalDuration: TimeInterval
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        guard !removals.isEmpty else {
            return [(start: 0, end: totalDuration)]
        }

        var regions: [(start: TimeInterval, end: TimeInterval)] = []
        var lastEnd: TimeInterval = 0

        for removal in removals {
            if removal.start > lastEnd {
                regions.append((start: lastEnd, end: removal.start))
            }
            lastEnd = removal.end
        }

        if lastEnd < totalDuration {
            regions.append((start: lastEnd, end: totalDuration))
        }

        return regions
    }

    /// 建立音訊 mix（用於 crossfade）
    private func createAudioMix(
        for track: AVMutableCompositionTrack,
        keepRegions: [(start: TimeInterval, end: TimeInterval)]
    ) -> AVMutableAudioMix? {
        guard keepRegions.count > 1 else { return nil }

        let audioMix = AVMutableAudioMix()
        let inputParams = AVMutableAudioMixInputParameters(track: track)

        var rampPoints: [(time: CMTime, volume: Float)] = []
        var currentTime = CMTime.zero
        let fadeDuration = CMTime(seconds: configuration.crossfadeDuration, preferredTimescale: 44100)

        for (index, region) in keepRegions.enumerated() {
            let duration = CMTime(seconds: region.end - region.start, preferredTimescale: 44100)

            if index > 0 {
                // Fade in
                rampPoints.append((time: currentTime, volume: 0))
                rampPoints.append((time: CMTimeAdd(currentTime, fadeDuration), volume: 1))
            }

            if index < keepRegions.count - 1 {
                // Fade out
                let endTime = CMTimeAdd(currentTime, duration)
                let fadeStartTime = CMTimeSubtract(endTime, fadeDuration)
                rampPoints.append((time: fadeStartTime, volume: 1))
                rampPoints.append((time: endTime, volume: 0))
            }

            currentTime = CMTimeAdd(currentTime, duration)
        }

        // 應用 volume ramps
        for i in stride(from: 0, to: rampPoints.count - 1, by: 2) {
            inputParams.setVolumeRamp(
                fromStartVolume: rampPoints[i].volume,
                toEndVolume: rampPoints[i + 1].volume,
                timeRange: CMTimeRange(
                    start: rampPoints[i].time,
                    end: rampPoints[i + 1].time
                )
            )
        }

        audioMix.inputParameters = [inputParams]
        return audioMix
    }

    /// 匯出 composition
    private func exportComposition(
        composition: AVMutableComposition,
        audioMix: AVMutableAudioMix?,
        to outputURL: URL
    ) async throws {
        // 刪除已存在的檔案
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioEditorError.exportFailed("無法建立匯出 session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = audioMix

        await exportSession.export()

        if let error = exportSession.error {
            throw AudioEditorError.exportFailed(error.localizedDescription)
        }

        guard exportSession.status == .completed else {
            throw AudioEditorError.exportFailed("匯出狀態: \(exportSession.status.rawValue)")
        }
    }
}

/// 音訊編輯器錯誤
public enum AudioEditorError: Error, LocalizedError {
    case noAudioTrack
    case invalidFormat
    case compositionFailed
    case exportFailed(String)
    case fileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "找不到音訊軌道"
        case .invalidFormat:
            return "無效的音訊格式"
        case .compositionFailed:
            return "無法建立 composition"
        case .exportFailed(let message):
            return "匯出失敗: \(message)"
        case .fileNotFound(let url):
            return "找不到檔案: \(url.lastPathComponent)"
        }
    }
}
