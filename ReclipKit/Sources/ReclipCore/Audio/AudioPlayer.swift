import Foundation
import AVFoundation
import Combine

/// 音訊播放器
@MainActor
public final class AudioPlayer: ObservableObject {
    // MARK: - Published Properties

    /// 播放狀態
    @Published public private(set) var isPlaying: Bool = false

    /// 目前播放時間（秒）
    @Published public private(set) var currentTime: TimeInterval = 0

    /// 總長度（秒）
    @Published public private(set) var duration: TimeInterval = 0

    /// 播放速度
    @Published public var playbackRate: Float = 1.0 {
        didSet {
            player?.rate = isPlaying ? playbackRate : 0
        }
    }

    /// 音量 (0.0 - 1.0)
    @Published public var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }

    /// 是否已載入音訊
    @Published public private(set) var isLoaded: Bool = false

    /// 錯誤
    @Published public private(set) var error: Error?

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    /// 時間更新回調
    public var onTimeUpdate: ((TimeInterval) -> Void)?

    // MARK: - Initialization

    public init() {}

    // Note: cleanup() should be called explicitly before releasing
    // since deinit cannot call @MainActor methods

    // MARK: - Public Methods

    /// 載入音訊檔案
    public func load(url: URL) async throws {
        cleanup()

        // 建立 AVAsset
        let asset = AVURLAsset(url: url)

        // 載入時長
        let loadedDuration = try await asset.load(.duration)
        self.duration = loadedDuration.seconds

        // 建立 PlayerItem
        let item = AVPlayerItem(asset: asset)
        self.playerItem = item

        // 建立 Player
        let player = AVPlayer(playerItem: item)
        player.volume = volume
        self.player = player

        // 監聽播放結束
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackEnded()
            }
            .store(in: &cancellables)

        // 設定時間觀察器（每 0.05 秒更新一次）
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
                self?.onTimeUpdate?(time.seconds)
            }
        }

        isLoaded = true
        currentTime = 0
        error = nil
    }

    /// 播放
    public func play() {
        guard isLoaded, let player else { return }

        player.rate = playbackRate
        isPlaying = true
    }

    /// 暫停
    public func pause() {
        guard let player else { return }

        player.pause()
        isPlaying = false
    }

    /// 切換播放/暫停
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// 跳轉到指定時間
    public func seek(to time: TimeInterval) async {
        guard let player else { return }

        let targetTime = CMTime(seconds: max(0, min(time, duration)), preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        await player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentTime = targetTime.seconds
    }

    /// 快進指定秒數
    public func skipForward(seconds: TimeInterval = 5) async {
        await seek(to: currentTime + seconds)
    }

    /// 快退指定秒數
    public func skipBackward(seconds: TimeInterval = 5) async {
        await seek(to: currentTime - seconds)
    }

    /// 停止並重置
    public func stop() {
        pause()
        Task {
            await seek(to: 0)
        }
    }

    /// 卸載音訊
    public func unload() {
        cleanup()
        isLoaded = false
        duration = 0
        currentTime = 0
    }

    // MARK: - Private Methods

    private func cleanup() {
        pause()

        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        cancellables.removeAll()
        playerItem = nil
        player = nil
    }

    private func handlePlaybackEnded() {
        isPlaying = false
        currentTime = duration
    }
}

// MARK: - Time Formatting

extension AudioPlayer {
    /// 格式化時間為 MM:SS 或 HH:MM:SS
    public static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }

        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    /// 目前時間的格式化字串
    public var currentTimeString: String {
        Self.formatTime(currentTime)
    }

    /// 總長度的格式化字串
    public var durationString: String {
        Self.formatTime(duration)
    }

    /// 剩餘時間的格式化字串
    public var remainingTimeString: String {
        Self.formatTime(duration - currentTime)
    }
}
