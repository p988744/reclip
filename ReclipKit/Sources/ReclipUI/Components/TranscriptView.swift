import SwiftUI
import ReclipCore

/// 逐字稿顯示視圖
public struct TranscriptView: View {
    let transcript: TranscriptResult
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var searchText: String = ""
    @State private var showWordLevel: Bool = false

    public init(
        transcript: TranscriptResult,
        currentTime: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.transcript = transcript
        self.currentTime = currentTime
        self.onSeek = onSeek
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 工具列
            toolbar

            Divider()

            // 逐字稿內容
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredSegments) { segment in
                            SegmentRow(
                                segment: segment,
                                isActive: isSegmentActive(segment),
                                showWordLevel: showWordLevel,
                                currentTime: currentTime,
                                onSeek: onSeek
                            )
                            .id(segment.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: currentTime) { _, newTime in
                    // 自動捲動到目前播放的段落
                    if let activeSegment = transcript.segments.first(where: { isSegmentActive($0) }) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(activeSegment.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: GlassStyle.cornerRadius)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.cornerRadius))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // 搜尋
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜尋逐字稿...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
            }

            Divider()
                .frame(height: 20)

            // 顯示選項
            Toggle("顯示詞級時間戳", isOn: $showWordLevel)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            // 統計資訊
            HStack(spacing: 16) {
                Label("\(transcript.segments.count) 段", systemImage: "text.bubble")
                Label(formatDuration(transcript.duration), systemImage: "clock")
                Label(languageName(transcript.language), systemImage: "globe")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Filtered Segments

    private var filteredSegments: [Segment] {
        if searchText.isEmpty {
            return transcript.segments
        }
        return transcript.segments.filter { segment in
            segment.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Helpers

    private func isSegmentActive(_ segment: Segment) -> Bool {
        currentTime >= segment.start && currentTime < segment.end
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    private func languageName(_ code: String) -> String {
        let names: [String: String] = [
            "zh": "中文",
            "en": "English",
            "ja": "日本語",
            "ko": "한국어",
            "es": "Español",
            "fr": "Français",
            "de": "Deutsch",
            "it": "Italiano",
            "pt": "Português",
            "ru": "Русский",
            "ar": "العربية",
            "hi": "हिन्दी"
        ]
        return names[code] ?? code
    }
}

// MARK: - Segment Row

struct SegmentRow: View {
    let segment: Segment
    let isActive: Bool
    let showWordLevel: Bool
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 時間戳記和說話者
            HStack(spacing: 12) {
                Button {
                    onSeek(segment.start)
                } label: {
                    Text(formatTimestamp(segment.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isActive ? .blue : .secondary)
                }
                .buttonStyle(.borderless)

                if let speaker = segment.speaker {
                    GlassBadge(speaker, color: .purple)
                }

                Spacer()

                Text(formatDuration(segment.duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // 文字內容
            if showWordLevel && !segment.words.isEmpty {
                // 詞級顯示
                wordLevelView
            } else {
                // 段落級顯示
                Text(segment.text)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.blue.opacity(0.1) : Color.clear)
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek(segment.start)
        }
    }

    private var wordLevelView: some View {
        FlowLayout(spacing: 4) {
            ForEach(segment.words) { word in
                WordView(
                    word: word,
                    isActive: currentTime >= word.start && currentTime < word.end,
                    onSeek: onSeek
                )
            }
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.0fs", seconds)
    }
}

// MARK: - Word View

struct WordView: View {
    let word: WordSegment
    let isActive: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        Text(word.word)
            .font(.body)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.3))
                }
            }
            .foregroundStyle(isActive ? .primary : .secondary)
            .opacity(confidenceOpacity)
            .onTapGesture {
                onSeek(word.start)
            }
    }

    private var confidenceOpacity: Double {
        // 根據信心度調整透明度
        0.5 + (word.confidence * 0.5)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(in: proposal.width ?? 0, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(in: bounds.width, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func layoutSubviews(in width: CGFloat, subviews: Subviews) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (positions, currentY + lineHeight)
    }
}

// MARK: - Compact Transcript View (for sidebar)

public struct CompactTranscriptView: View {
    let transcript: TranscriptResult
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void

    public init(
        transcript: TranscriptResult,
        currentTime: TimeInterval,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        self.transcript = transcript
        self.currentTime = currentTime
        self.onSeek = onSeek
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(transcript.segments) { segment in
                        CompactSegmentRow(
                            segment: segment,
                            isActive: currentTime >= segment.start && currentTime < segment.end,
                            onSeek: onSeek
                        )
                        .id(segment.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: currentTime) { _, _ in
                if let activeSegment = transcript.segments.first(where: {
                    currentTime >= $0.start && currentTime < $0.end
                }) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(activeSegment.id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct CompactSegmentRow: View {
    let segment: Segment
    let isActive: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTime(segment.start))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)

            Text(segment.text)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.1))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek(segment.start)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    let sampleTranscript = TranscriptResult(
        segments: [
            Segment(text: "大家好，歡迎收聽我們的 Podcast。", start: 0, end: 3.5),
            Segment(text: "今天我們要討論的主題是軟體開發中的最佳實踐。", start: 3.5, end: 8.2),
            Segment(text: "嗯，就是說，這個話題其實非常重要。", start: 8.2, end: 12.0),
            Segment(text: "讓我們從代碼審查開始說起吧。", start: 12.0, end: 15.5),
        ],
        language: "zh",
        duration: 15.5
    )

    TranscriptView(
        transcript: sampleTranscript,
        currentTime: 9.0,
        onSeek: { time in print("Seek to: \(time)") }
    )
    .frame(width: 600, height: 400)
    .padding()
}
