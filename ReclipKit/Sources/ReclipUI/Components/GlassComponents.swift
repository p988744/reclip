import SwiftUI

/// Liquid Glass 樣式常數
public enum GlassStyle {
    /// 標準圓角半徑
    public static let cornerRadius: CGFloat = 16

    /// 大圓角半徑
    public static let largeCornerRadius: CGFloat = 24

    /// 小圓角半徑
    public static let smallCornerRadius: CGFloat = 8

    /// 標準間距
    public static let spacing: CGFloat = 12

    /// 標準內邊距
    public static let padding: CGFloat = 16

    /// 動畫時長
    public static let animationDuration: Double = 0.3
}

// MARK: - Glass Panel

/// 玻璃面板容器
public struct GlassPanel<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(GlassStyle.padding)
            .background {
                RoundedRectangle(cornerRadius: GlassStyle.cornerRadius)
                    .fill(.regularMaterial)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.cornerRadius))
    }
}

// MARK: - Glass Card

/// 玻璃卡片
public struct GlassCard<Content: View>: View {
    let title: String?
    let content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlassStyle.spacing) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(GlassStyle.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: GlassStyle.cornerRadius)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: GlassStyle.cornerRadius))
    }
}

// MARK: - Glass Button

/// 玻璃按鈕樣式
public struct GlassButtonStyle: ButtonStyle {
    let tint: Color?

    public init(tint: Color? = nil) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(.regularMaterial)
            }
            .glassEffect(
                tint.map { .regular.tint($0) } ?? .regular,
                in: .capsule
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    public static var glass: GlassButtonStyle { GlassButtonStyle() }

    public static func glass(tint: Color) -> GlassButtonStyle {
        GlassButtonStyle(tint: tint)
    }
}

// MARK: - Glass Toolbar

/// 玻璃工具列
public struct GlassToolbar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: GlassStyle.spacing) {
            content
        }
        .padding(.horizontal, GlassStyle.padding)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Glass Segmented Control

/// 玻璃分段控制
public struct GlassSegmentedPicker<SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue
    let content: Content

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self._selection = selection
        self.content = content()
    }

    public var body: some View {
        Picker("", selection: $selection) {
            content
        }
        .pickerStyle(.segmented)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Glass Progress

/// 玻璃進度條
public struct GlassProgress: View {
    let value: Double
    let total: Double
    let label: String?

    public init(value: Double, total: Double = 1.0, label: String? = nil) {
        self.value = value
        self.total = total
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(value / total * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular, in: .capsule)

                    // 進度
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(0, geometry.size.width * (value / total)))
                        .glassEffect(.regular.tint(.accentColor), in: .capsule)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Glass Badge

/// 玻璃徽章
public struct GlassBadge: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = .accentColor) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
            .glassEffect(.regular.tint(color), in: .capsule)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        GlassCard(title: "音訊資訊") {
            VStack(alignment: .leading, spacing: 8) {
                Text("podcast_episode_01.wav")
                    .font(.body)
                Text("時長: 45:32")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        GlassToolbar {
            Button("轉錄", systemImage: "waveform") { }
            Button("分析", systemImage: "sparkles") { }
            Button("剪輯", systemImage: "scissors") { }
        }

        Button("開始處理") { }
            .buttonStyle(.glass(tint: .blue))

        GlassProgress(value: 0.65, label: "處理進度")
            .padding(.horizontal)

        HStack {
            GlassBadge("filler", color: .orange)
            GlassBadge("repeat", color: .purple)
            GlassBadge("pause", color: .gray)
        }
    }
    .padding()
    .frame(width: 400, height: 500)
    .background(Color.blue.gradient)
}
