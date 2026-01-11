import SwiftUI
import ReclipCore

/// 播放控制元件
public struct PlaybackControls: View {
    // MARK: - Properties

    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var playbackRate: Float

    let duration: TimeInterval
    let onPlay: () -> Void
    let onPause: () -> Void
    let onSeek: (TimeInterval) async -> Void
    let onSkipForward: () async -> Void
    let onSkipBackward: () async -> Void

    // MARK: - State

    @State private var isSeeking: Bool = false
    @State private var seekTime: TimeInterval = 0
    @State private var showRatePopover: Bool = false

    // MARK: - Constants

    private let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    public init(
        isPlaying: Binding<Bool>,
        currentTime: Binding<TimeInterval>,
        playbackRate: Binding<Float>,
        duration: TimeInterval,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) async -> Void,
        onSkipForward: @escaping () async -> Void,
        onSkipBackward: @escaping () async -> Void
    ) {
        self._isPlaying = isPlaying
        self._currentTime = currentTime
        self._playbackRate = playbackRate
        self.duration = duration
        self.onPlay = onPlay
        self.onPause = onPause
        self.onSeek = onSeek
        self.onSkipForward = onSkipForward
        self.onSkipBackward = onSkipBackward
    }

    public var body: some View {
        VStack(spacing: 12) {
            // 時間軸滑桿
            timelineSlider

            // 控制按鈕
            HStack(spacing: 24) {
                // 時間顯示
                timeDisplay

                Spacer()

                // 主控制區
                mainControls

                Spacer()

                // 播放速度
                rateControl
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: GlassStyle.cornerRadius)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.cornerRadius))
    }

    // MARK: - Timeline Slider

    private var timelineSlider: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景軌道
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 8)

                // 進度
                let progress = duration > 0 ? (isSeeking ? seekTime : currentTime) / duration : 0
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(progress), height: 8)

                // 拖曳手柄
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: geometry.size.width * CGFloat(progress) - 8)
            }
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isSeeking = true
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        seekTime = duration * Double(progress)
                    }
                    .onEnded { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        let time = duration * Double(progress)
                        Task {
                            await onSeek(time)
                            isSeeking = false
                        }
                    }
            )
        }
        .frame(height: 16)
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        HStack(spacing: 4) {
            Text(formatTime(isSeeking ? seekTime : currentTime))
                .font(.body.monospacedDigit())

            Text("/")
                .foregroundStyle(.secondary)

            Text(formatTime(duration))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 120, alignment: .leading)
    }

    // MARK: - Main Controls

    private var mainControls: some View {
        HStack(spacing: 16) {
            // 快退 5 秒
            Button {
                Task { await onSkipBackward() }
            } label: {
                Image(systemName: "gobackward.5")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.leftArrow, modifiers: [])

            // 播放/暫停
            Button {
                if isPlaying {
                    onPause()
                } else {
                    onPlay()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])

            // 快進 5 秒
            Button {
                Task { await onSkipForward() }
            } label: {
                Image(systemName: "goforward.5")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    // MARK: - Rate Control

    private var rateControl: some View {
        Button {
            showRatePopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                Text("\(playbackRate, specifier: "%.2f")x")
                    .font(.body.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showRatePopover) {
            VStack(spacing: 8) {
                ForEach(availableRates, id: \.self) { rate in
                    Button {
                        playbackRate = rate
                        showRatePopover = false
                    } label: {
                        HStack {
                            Text("\(rate, specifier: "%.2f")x")
                                .font(.body.monospacedDigit())

                            Spacer()

                            if playbackRate == rate {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .frame(width: 120)
        }
        .frame(minWidth: 100, alignment: .trailing)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
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
}

// MARK: - Compact Playback Controls

/// 緊湊版播放控制（用於工具列）
public struct CompactPlaybackControls: View {
    @Binding var isPlaying: Bool
    let onToggle: () -> Void
    let onSkipBackward: () -> Void
    let onSkipForward: () -> Void

    public init(
        isPlaying: Binding<Bool>,
        onToggle: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void,
        onSkipForward: @escaping () -> Void
    ) {
        self._isPlaying = isPlaying
        self.onToggle = onToggle
        self.onSkipBackward = onSkipBackward
        self.onSkipForward = onSkipForward
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onSkipBackward) {
                Image(systemName: "gobackward.5")
            }
            .buttonStyle(.borderless)

            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)

            Button(action: onSkipForward) {
                Image(systemName: "goforward.5")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Mini Time Display

/// 迷你時間顯示
public struct MiniTimeDisplay: View {
    let currentTime: TimeInterval
    let duration: TimeInterval

    public init(currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
    }

    public var body: some View {
        Text("\(formatTime(currentTime)) / \(formatTime(duration))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isPlaying = false
        @State private var currentTime: TimeInterval = 125
        @State private var playbackRate: Float = 1.0

        var body: some View {
            VStack(spacing: 20) {
                PlaybackControls(
                    isPlaying: $isPlaying,
                    currentTime: $currentTime,
                    playbackRate: $playbackRate,
                    duration: 3600,
                    onPlay: { isPlaying = true },
                    onPause: { isPlaying = false },
                    onSeek: { time in currentTime = time },
                    onSkipForward: { currentTime = min(3600, currentTime + 5) },
                    onSkipBackward: { currentTime = max(0, currentTime - 5) }
                )

                CompactPlaybackControls(
                    isPlaying: $isPlaying,
                    onToggle: { isPlaying.toggle() },
                    onSkipBackward: { currentTime = max(0, currentTime - 5) },
                    onSkipForward: { currentTime = min(3600, currentTime + 5) }
                )

                MiniTimeDisplay(currentTime: currentTime, duration: 3600)
            }
            .padding()
            .frame(width: 600, height: 300)
            .background(Color.black.opacity(0.8))
        }
    }

    return PreviewWrapper()
}
