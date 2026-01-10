import SwiftUI
import ReclipCore

/// 多說話者時間軸視圖 - 類似甘特圖的說話者分布顯示
public struct SpeakerTimelineView: View {
    let transcript: TranscriptResult
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var hoveredSegment: Segment?
    @State private var hoverLocation: CGPoint = .zero
    @State private var containerWidth: CGFloat = 0

    // 說話者顏色
    private let speakerColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo
    ]

    public init(
        transcript: TranscriptResult,
        currentTime: TimeInterval,
        duration: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.transcript = transcript
        self.currentTime = currentTime
        self.duration = duration
        self.onSeek = onSeek
    }

    /// 取得所有說話者（按出現順序）
    private var speakers: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for segment in transcript.segments {
            let speaker = segment.speaker ?? "說話者"
            if !seen.contains(speaker) {
                seen.insert(speaker)
                result.append(speaker)
            }
        }
        return result.isEmpty ? ["說話者"] : result
    }

    /// 依說話者分組的片段
    private var segmentsBySpeaker: [String: [Segment]] {
        var result: [String: [Segment]] = [:]
        for speaker in speakers {
            result[speaker] = []
        }
        for segment in transcript.segments {
            let speaker = segment.speaker ?? "說話者"
            result[speaker, default: []].append(segment)
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 時間軸標尺
            TimeRuler(duration: duration, width: containerWidth)
                .frame(height: 24)

            // 說話者軌道
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(speakers.enumerated()), id: \.element) { index, speaker in
                        SpeakerTrack(
                            speaker: speaker,
                            segments: segmentsBySpeaker[speaker] ?? [],
                            color: speakerColors[index % speakerColors.count],
                            duration: duration,
                            currentTime: currentTime,
                            hoveredSegment: $hoveredSegment,
                            hoverLocation: $hoverLocation,
                            onSeek: onSeek
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            // 播放頭指示器疊加
            GeometryReader { geometry in
                let x = geometry.size.width * (currentTime / max(duration, 1))

                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: x)
                    .allowsHitTesting(false)
            }
            .frame(height: 0) // 只用於疊加定位
        }
        .background(
            GeometryReader { geometry in
                Color.clear.onAppear {
                    containerWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
            }
        )
        .overlay(alignment: .topLeading) {
            // Hover 提示框
            if let segment = hoveredSegment {
                SegmentTooltip(segment: segment)
                    .offset(x: hoverLocation.x, y: hoverLocation.y - 60)
            }
        }
    }
}

// MARK: - Time Ruler

struct TimeRuler: View {
    let duration: TimeInterval
    let width: CGFloat

    private var tickInterval: TimeInterval {
        if duration < 60 { return 10 }
        if duration < 300 { return 30 }
        if duration < 600 { return 60 }
        if duration < 1800 { return 120 }
        return 300
    }

    private var ticks: [TimeInterval] {
        guard duration > 0, width > 0 else { return [] }
        var result: [TimeInterval] = []
        var t: TimeInterval = 0
        while t <= duration {
            result.append(t)
            t += tickInterval
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景
            Rectangle()
                .fill(.ultraThinMaterial)

            // 刻度線和標籤
            ForEach(ticks, id: \.self) { time in
                let x = width * (time / max(duration, 1))

                VStack(spacing: 2) {
                    Text(formatTime(time))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Rectangle()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 1, height: 6)
                }
                .position(x: x, y: 12)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Speaker Track

struct SpeakerTrack: View {
    let speaker: String
    let segments: [Segment]
    let color: Color
    let duration: TimeInterval
    let currentTime: TimeInterval
    @Binding var hoveredSegment: Segment?
    @Binding var hoverLocation: CGPoint
    let onSeek: (TimeInterval) -> Void

    private let trackHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            // 說話者標籤
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)

                Text(speaker)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: 80, alignment: .leading)
            .padding(.horizontal, 8)

            // 時間軸軌道
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 軌道背景
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.1))

                    // 片段
                    ForEach(segments) { segment in
                        SegmentBlock(
                            segment: segment,
                            color: color,
                            duration: duration,
                            trackWidth: geometry.size.width,
                            isHovered: hoveredSegment?.id == segment.id,
                            onHover: { isHovering, location in
                                if isHovering {
                                    hoveredSegment = segment
                                    hoverLocation = location
                                } else if hoveredSegment?.id == segment.id {
                                    hoveredSegment = nil
                                }
                            },
                            onTap: {
                                onSeek(segment.start)
                            }
                        )
                    }

                    // 播放頭
                    let playheadX = geometry.size.width * (currentTime / max(duration, 1))
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: trackHeight)
                        .offset(x: playheadX)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: trackHeight)
        }
    }
}

// MARK: - Segment Block

struct SegmentBlock: View {
    let segment: Segment
    let color: Color
    let duration: TimeInterval
    let trackWidth: CGFloat
    let isHovered: Bool
    let onHover: (Bool, CGPoint) -> Void
    let onTap: () -> Void

    @State private var isPressed = false

    private var startX: CGFloat {
        trackWidth * (segment.start / max(duration, 1))
    }

    private var width: CGFloat {
        max(4, trackWidth * (segment.duration / max(duration, 1)))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(isHovered ? 0.9 : 0.7))
            .frame(width: width, height: isHovered ? 28 : 24)
            .overlay {
                // 如果寬度夠，顯示文字預覽
                if width > 60 {
                    Text(segment.text)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            .shadow(color: color.opacity(isHovered ? 0.5 : 0), radius: 4)
            .offset(x: startX)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onHover { hovering in
                onHover(hovering, CGPoint(x: startX + width / 2, y: 0))
            }
            .onTapGesture {
                onTap()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - Segment Tooltip

struct SegmentTooltip: View {
    let segment: Segment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 時間範圍
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("\(formatTime(segment.start)) → \(formatTime(segment.end))")
                    .font(.caption.monospacedDigit())

                Text("(\(formatDuration(segment.duration)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 說話者
            if let speaker = segment.speaker {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text(speaker)
                        .font(.caption.weight(.medium))
                }
            }

            Divider()

            // 內容
            Text(segment.text)
                .font(.callout)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview("Speaker Timeline") {
    let mockTranscript = TranscriptResult(
        segments: [
            Segment(text: "大家好，歡迎收聽本期節目", start: 0, end: 3, speaker: "主持人A"),
            Segment(text: "謝謝邀請，很高興來到這裡", start: 3.5, end: 6, speaker: "來賓B"),
            Segment(text: "今天我們要聊的主題是 Swift 開發", start: 6.5, end: 10, speaker: "主持人A"),
            Segment(text: "沒錯，這是一個很有趣的話題", start: 10.5, end: 13, speaker: "來賓B"),
            Segment(text: "我也有一些想法想分享", start: 13.5, end: 16, speaker: "來賓C"),
            Segment(text: "好的，請說", start: 16.5, end: 17.5, speaker: "主持人A"),
            Segment(text: "我認為 SwiftUI 改變了整個開發體驗", start: 18, end: 23, speaker: "來賓C"),
            Segment(text: "確實如此，尤其是宣告式語法", start: 23.5, end: 27, speaker: "來賓B"),
            Segment(text: "讓我們深入探討一下這個部分", start: 27.5, end: 30, speaker: "主持人A"),
        ],
        language: "zh",
        duration: 30
    )

    SpeakerTimelineView(
        transcript: mockTranscript,
        currentTime: 12,
        duration: 30,
        onSeek: { time in
            print("Seek to: \(time)")
        }
    )
    .frame(height: 200)
    .padding()
}

#Preview("Single Speaker") {
    let mockTranscript = TranscriptResult(
        segments: [
            Segment(text: "這是一段獨白", start: 0, end: 5, speaker: nil),
            Segment(text: "沒有說話者標記", start: 6, end: 10, speaker: nil),
            Segment(text: "所有內容都在同一軌道", start: 11, end: 15, speaker: nil),
        ],
        language: "zh",
        duration: 15
    )

    SpeakerTimelineView(
        transcript: mockTranscript,
        currentTime: 7,
        duration: 15,
        onSeek: { _ in }
    )
    .frame(height: 100)
    .padding()
}
