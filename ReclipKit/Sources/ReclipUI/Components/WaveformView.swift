import SwiftUI
import ReclipCore

/// 波形顯示視圖
public struct WaveformView: View {
    let samples: [Float]
    let removals: [Removal]
    let currentTime: TimeInterval
    let duration: TimeInterval

    @State private var hoveredRemoval: Removal?
    @Namespace private var waveformNamespace

    public init(
        samples: [Float],
        removals: [Removal] = [],
        currentTime: TimeInterval = 0,
        duration: TimeInterval
    ) {
        self.samples = samples
        self.removals = removals
        self.currentTime = currentTime
        self.duration = duration
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: GlassStyle.smallCornerRadius)
                    .fill(.ultraThinMaterial)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.smallCornerRadius))

                // 移除區域標記
                ForEach(removals) { removal in
                    removalOverlay(removal, in: geometry.size)
                }

                // 波形
                waveformPath(in: geometry.size)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )

                // 播放頭
                if duration > 0 {
                    playhead(in: geometry.size)
                }
            }
        }
        .frame(height: 120)
    }

    // MARK: - Waveform Path

    private func waveformPath(in size: CGSize) -> Path {
        Path { path in
            guard !samples.isEmpty else { return }

            let midY = size.height / 2
            let samplesPerPixel = max(1, samples.count / Int(size.width))

            for x in stride(from: 0, to: Int(size.width), by: 1) {
                let startIndex = x * samplesPerPixel
                let endIndex = min(startIndex + samplesPerPixel, samples.count)

                guard startIndex < samples.count else { break }

                // 取該區間的最大值和最小值
                let slice = samples[startIndex..<endIndex]
                let maxVal = slice.max() ?? 0
                let minVal = slice.min() ?? 0

                let topY = midY - CGFloat(maxVal) * midY * 0.9
                let bottomY = midY - CGFloat(minVal) * midY * 0.9

                if x == 0 {
                    path.move(to: CGPoint(x: CGFloat(x), y: topY))
                }

                path.addLine(to: CGPoint(x: CGFloat(x), y: topY))
                path.addLine(to: CGPoint(x: CGFloat(x), y: bottomY))
            }
        }
    }

    // MARK: - Removal Overlay

    private func removalOverlay(_ removal: Removal, in size: CGSize) -> some View {
        let startX = CGFloat(removal.start / duration) * size.width
        let endX = CGFloat(removal.end / duration) * size.width
        let width = endX - startX

        return Rectangle()
            .fill(colorForReason(removal.reason).opacity(0.3))
            .frame(width: max(2, width))
            .offset(x: startX)
            .overlay(alignment: .top) {
                if hoveredRemoval?.id == removal.id {
                    removalTooltip(removal)
                        .offset(y: -40)
                }
            }
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredRemoval = isHovering ? removal : nil
                }
            }
    }

    private func removalTooltip(_ removal: Removal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                GlassBadge(removal.reason.displayName, color: colorForReason(removal.reason))

                Text(String(format: "%.2fs", removal.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(removal.text)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Playhead

    private func playhead(in size: CGSize) -> some View {
        let x = CGFloat(currentTime / duration) * size.width

        return Rectangle()
            .fill(.white)
            .frame(width: 2)
            .shadow(color: .white.opacity(0.5), radius: 4)
            .offset(x: x)
    }

    // MARK: - Helpers

    private func colorForReason(_ reason: RemovalReason) -> Color {
        switch reason {
        case .filler: return .orange
        case .repair: return .purple
        case .restart: return .blue
        case .mouthNoise: return .pink
        case .longPause: return .gray
        }
    }
}

// MARK: - Removal Reason Display

extension RemovalReason {
    public var displayName: String {
        switch self {
        case .filler: return "語氣詞"
        case .repair: return "修正"
        case .restart: return "重說"
        case .mouthNoise: return "雜音"
        case .longPause: return "長停頓"
        }
    }
}

// MARK: - Preview

#Preview {
    // 生成模擬波形資料
    let samples: [Float] = (0..<1000).map { i in
        let t = Float(i) / 1000
        return sin(t * 50) * (0.3 + 0.7 * sin(t * 5)) * Float.random(in: 0.8...1.0)
    }

    let removals = [
        Removal(start: 5, end: 6, reason: .filler, text: "嗯"),
        Removal(start: 15, end: 17, reason: .repair, text: "就是說 就是說"),
        Removal(start: 25, end: 26.5, reason: .longPause, text: ""),
    ]

    VStack {
        WaveformView(
            samples: samples,
            removals: removals,
            currentTime: 10,
            duration: 60
        )
        .padding()
    }
    .frame(width: 600, height: 200)
    .background(Color.black.opacity(0.8))
}
