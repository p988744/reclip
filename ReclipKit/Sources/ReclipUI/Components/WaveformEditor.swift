import SwiftUI
import AppKit
import ReclipCore

/// 編輯區間資料結構
public struct EditRegion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var isSelected: Bool

    public var duration: TimeInterval { end - start }

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, isSelected: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.isSelected = isSelected
    }
}

/// 波形編輯器 - 支援選取、刪除、移動補上功能
public struct WaveformEditor: View {
    // MARK: - Properties

    let samples: [Float]
    let duration: TimeInterval
    @Binding var currentTime: TimeInterval
    @Binding var editRegions: [EditRegion]
    @Binding var selectedRegionID: UUID?

    let onSeek: (TimeInterval) -> Void
    let onDelete: (EditRegion) -> Void
    let onMoveAndFill: (EditRegion) -> Void

    // MARK: - State

    @State private var isDragging: Bool = false
    @State private var dragStart: CGFloat = 0
    @State private var dragEnd: CGFloat = 0
    @State private var isCreatingSelection: Bool = false
    @State private var hoveredRegionID: UUID?
    @State private var zoomLevel: Double = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrubbing: Bool = false // 正在拖曳播放頭

    // MARK: - Constants

    private let waveformHeight: CGFloat = 120
    private let timelineHeight: CGFloat = 24
    private let minSelectionWidth: CGFloat = 10

    public init(
        samples: [Float],
        duration: TimeInterval,
        currentTime: Binding<TimeInterval>,
        editRegions: Binding<[EditRegion]>,
        selectedRegionID: Binding<UUID?>,
        onSeek: @escaping (TimeInterval) -> Void,
        onDelete: @escaping (EditRegion) -> Void,
        onMoveAndFill: @escaping (EditRegion) -> Void
    ) {
        self.samples = samples
        self.duration = duration
        self._currentTime = currentTime
        self._editRegions = editRegions
        self._selectedRegionID = selectedRegionID
        self.onSeek = onSeek
        self.onDelete = onDelete
        self.onMoveAndFill = onMoveAndFill
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 工具列
            editorToolbar

            // 波形編輯區
            GeometryReader { geometry in
                let contentWidth = geometry.size.width * zoomLevel

                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // 背景
                        RoundedRectangle(cornerRadius: GlassStyle.smallCornerRadius)
                            .fill(.ultraThinMaterial)

                        // 時間軸
                        timelineView(width: contentWidth)
                            .frame(height: timelineHeight)

                        // 波形
                        waveformView(width: contentWidth)
                            .offset(y: timelineHeight)

                        // 編輯區域
                        ForEach(editRegions) { region in
                            editRegionOverlay(region, width: contentWidth)
                                .offset(y: timelineHeight)
                        }

                        // 選取中的區域
                        if isCreatingSelection {
                            selectionPreview(width: contentWidth)
                                .offset(y: timelineHeight)
                        }

                        // 播放頭
                        playhead(width: contentWidth)
                    }
                    .frame(width: contentWidth, height: waveformHeight + timelineHeight)
                    .contentShape(Rectangle())
                    .gesture(editorGesture(width: contentWidth))
                }
            }
            .frame(height: waveformHeight + timelineHeight)
            .background {
                RoundedRectangle(cornerRadius: GlassStyle.cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.cornerRadius))

            // 選取區域資訊
            if let selectedID = selectedRegionID,
               let region = editRegions.first(where: { $0.id == selectedID }) {
                selectedRegionInfo(region)
            }
        }
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 16) {
            // 縮放控制
            HStack(spacing: 8) {
                Button(action: { zoomLevel = max(1.0, zoomLevel - 0.5) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text("\(Int(zoomLevel * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 50)

                Button(action: { zoomLevel = min(10.0, zoomLevel + 0.5) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
            }

            Divider()
                .frame(height: 20)

            // 選取工具提示
            Text("點擊跳轉 | 拖曳調整位置 | Shift+拖曳選取")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // 清除所有選取
            if !editRegions.isEmpty {
                Button("清除全部", systemImage: "trash") {
                    editRegions.removeAll()
                    selectedRegionID = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Timeline View

    private func timelineView(width: CGFloat) -> some View {
        Canvas { context, size in
            let majorInterval = calculateMajorInterval(duration: duration, width: width)

            // 繪製時間標記
            var time: TimeInterval = 0
            while time <= duration {
                let x = CGFloat(time / duration) * width

                // 主刻度
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: size.height - 8))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.secondary),
                    lineWidth: 1
                )

                // 時間標籤
                let timeString = formatTimeShort(time)
                context.draw(
                    Text(timeString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary),
                    at: CGPoint(x: x, y: 8)
                )

                time += majorInterval
            }
        }
    }

    // MARK: - Waveform View

    private func waveformView(width: CGFloat) -> some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let midY = size.height / 2
            let samplesPerPixel = max(1, samples.count / Int(width))

            var path = Path()

            for x in stride(from: 0, to: Int(width), by: 1) {
                let startIndex = x * samplesPerPixel
                let endIndex = min(startIndex + samplesPerPixel, samples.count)

                guard startIndex < samples.count else { break }

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

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.blue, .purple]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 1.5
            )
        }
        .frame(height: waveformHeight)
    }

    // MARK: - Edit Region Overlay

    private func editRegionOverlay(_ region: EditRegion, width: CGFloat) -> some View {
        let startX = CGFloat(region.start / duration) * width
        let endX = CGFloat(region.end / duration) * width
        let regionWidth = endX - startX
        let isSelected = selectedRegionID == region.id

        return Rectangle()
            .fill(isSelected ? Color.red.opacity(0.4) : Color.orange.opacity(0.3))
            .frame(width: max(2, regionWidth), height: waveformHeight)
            .overlay(alignment: .leading) {
                // 左邊界拖曳控制
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
            }
            .overlay(alignment: .trailing) {
                // 右邊界拖曳控制
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
            }
            .border(isSelected ? Color.red : Color.orange, width: isSelected ? 2 : 1)
            .offset(x: startX)
            .onTapGesture {
                selectedRegionID = region.id
            }
            .onHover { hovering in
                hoveredRegionID = hovering ? region.id : nil
            }
            .contextMenu {
                Button("刪除此區間", systemImage: "trash", role: .destructive) {
                    onDelete(region)
                }

                Button("移動補上", systemImage: "arrow.left.arrow.right") {
                    onMoveAndFill(region)
                }

                Divider()

                Button("取消選取") {
                    if selectedRegionID == region.id {
                        selectedRegionID = nil
                    }
                }
            }
    }

    // MARK: - Selection Preview

    private func selectionPreview(width: CGFloat) -> some View {
        let startX = min(dragStart, dragEnd)
        let endX = max(dragStart, dragEnd)
        let selectionWidth = endX - startX

        return Rectangle()
            .fill(Color.blue.opacity(0.3))
            .frame(width: max(2, selectionWidth), height: waveformHeight)
            .border(Color.blue, width: 2)
            .offset(x: startX)
    }

    // MARK: - Playhead

    private func playhead(width: CGFloat) -> some View {
        let x = CGFloat(currentTime / duration) * width

        return VStack(spacing: 0) {
            // 頂部三角形
            Triangle()
                .fill(Color.white)
                .frame(width: 12, height: 8)
                .offset(y: -timelineHeight + 4)

            // 線條
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: waveformHeight + timelineHeight - 4)
                .shadow(color: .white.opacity(0.5), radius: 4)
        }
        .offset(x: x - 1)
    }

    // MARK: - Selected Region Info

    private func selectedRegionInfo(_ region: EditRegion) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("選取區間")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(formatTime(region.start)) - \(formatTime(region.end))")
                    .font(.body.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("長度")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formatTime(region.duration))
                    .font(.body.monospacedDigit())
            }

            Spacer()

            Button("刪除", systemImage: "trash", role: .destructive) {
                onDelete(region)
            }
            .buttonStyle(.reclipGlass(tint: .red))

            Button("移動補上", systemImage: "arrow.left.arrow.right") {
                onMoveAndFill(region)
            }
            .buttonStyle(.reclipGlass(tint: .blue))
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: GlassStyle.smallCornerRadius)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.smallCornerRadius))
        .padding(.top, 8)
    }

    // MARK: - Gesture

    private func editorGesture(width: CGFloat) -> some Gesture {
        // 拖曳手勢
        let dragGesture = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let location = value.location
                let isShiftPressed = NSEvent.modifierFlags.contains(.shift)

                // Shift+拖曳：選取模式
                if isShiftPressed {
                    // 忽略時間軸區域的拖曳
                    guard location.y > timelineHeight else { return }

                    if !isCreatingSelection {
                        // 檢查是否有足夠的移動距離才開始選取
                        let distance = abs(value.location.x - value.startLocation.x)
                        if distance > 5 {
                            isCreatingSelection = true
                            dragStart = value.startLocation.x
                        }
                    }

                    if isCreatingSelection {
                        dragEnd = location.x
                    }
                    return
                }

                // 一般拖曳：調整播放位置 (scrub)
                let distance = abs(value.location.x - value.startLocation.x)
                if distance > 3 {
                    isScrubbing = true
                    let x = max(0, min(width, location.x))
                    let time = TimeInterval(x / width) * duration
                    onSeek(max(0, min(duration, time)))
                }
            }
            .onEnded { value in
                // Scrub 模式結束
                if isScrubbing {
                    isScrubbing = false
                    return
                }

                // 選取模式結束
                if isCreatingSelection {
                    let startX = min(dragStart, dragEnd)
                    let endX = max(dragStart, dragEnd)

                    // 確保選取區域足夠大
                    if endX - startX >= minSelectionWidth {
                        let startTime = TimeInterval(startX / width) * duration
                        let endTime = TimeInterval(endX / width) * duration

                        let newRegion = EditRegion(
                            start: max(0, startTime),
                            end: min(duration, endTime)
                        )

                        editRegions.append(newRegion)
                        selectedRegionID = newRegion.id
                    }

                    isCreatingSelection = false
                    dragStart = 0
                    dragEnd = 0
                    return
                }

                // 單擊跳轉到指定位置
                let x = max(0, min(width, value.location.x))
                let time = TimeInterval(x / width) * duration
                onSeek(max(0, min(duration, time)))
                selectedRegionID = nil
            }

        return dragGesture
    }

    // MARK: - Helpers

    private func calculateMajorInterval(duration: TimeInterval, width: CGFloat) -> TimeInterval {
        let targetMarks = width / 80 // 每 80 像素一個刻度
        let roughInterval = duration / targetMarks

        // 取整到合適的間隔
        let intervals: [TimeInterval] = [0.5, 1, 2, 5, 10, 30, 60, 120, 300, 600]
        return intervals.first { $0 >= roughInterval } ?? 60
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }

    private func formatTimeShort(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

// MARK: - Cursor Modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var currentTime: TimeInterval = 30
        @State private var editRegions: [EditRegion] = [
            EditRegion(start: 10, end: 15),
            EditRegion(start: 45, end: 50)
        ]
        @State private var selectedRegionID: UUID?

        var body: some View {
            let samples: [Float] = (0..<2000).map { i in
                let t = Float(i) / 2000
                return sin(t * 100) * (0.3 + 0.7 * sin(t * 10)) * Float.random(in: 0.7...1.0)
            }

            WaveformEditor(
                samples: samples,
                duration: 120,
                currentTime: $currentTime,
                editRegions: $editRegions,
                selectedRegionID: $selectedRegionID,
                onSeek: { time in currentTime = time },
                onDelete: { region in
                    editRegions.removeAll { $0.id == region.id }
                    if selectedRegionID == region.id {
                        selectedRegionID = nil
                    }
                },
                onMoveAndFill: { region in
                    print("Move and fill: \(region)")
                }
            )
            .padding()
            .frame(width: 800, height: 300)
            .background(Color.black.opacity(0.8))
        }
    }

    return PreviewWrapper()
}
