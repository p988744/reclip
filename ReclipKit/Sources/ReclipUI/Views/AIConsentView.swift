import SwiftUI
import ReclipCore

/// AI 資料處理同意對話框
/// 根據 App Store Guidelines 5.1.2，使用第三方 AI 前必須取得使用者同意
public struct AIConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = AppSettings.shared

    let onConsent: (LLMProviderType) -> Void

    public init(onConsent: @escaping (LLMProviderType) -> Void) {
        self.onConsent = onConsent
    }

    public var body: some View {
        VStack(spacing: 24) {
            // 標題
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("AI 分析說明")
                    .font(.title.weight(.semibold))

                Text("請選擇 AI 處理方式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            // 選項卡片
            VStack(spacing: 16) {
                // Claude API 選項
                AIOptionCard(
                    icon: "cloud",
                    title: "Claude API",
                    subtitle: "雲端處理",
                    description: "將逐字稿傳送至 Anthropic 伺服器進行分析。分析效果最佳，但需要網路連線。",
                    badge: "需要網路",
                    badgeColor: .blue,
                    privacyNote: "您的逐字稿會傳送至第三方伺服器",
                    isSelected: settings.llmProvider == .claude
                ) {
                    settings.llmProvider = .claude
                }

                // Ollama 選項
                AIOptionCard(
                    icon: "desktopcomputer",
                    title: "Ollama",
                    subtitle: "本地處理",
                    description: "在您的 Mac 上本地執行 AI 模型。資料不離開裝置，但需要安裝 Ollama。",
                    badge: "完全本地",
                    badgeColor: .green,
                    privacyNote: "所有資料都在您的裝置上處理",
                    isSelected: settings.llmProvider == .ollama
                ) {
                    settings.llmProvider = .ollama
                }
            }

            Divider()

            // 隱私說明
            VStack(alignment: .leading, spacing: 12) {
                Label("資料使用說明", systemImage: "lock.shield")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    privacyBullet("僅傳送逐字稿文字，不傳送原始音訊")
                    privacyBullet("資料僅用於識別需移除的內容")
                    privacyBullet("您可以隨時在設定中更改處理方式")

                    if settings.llmProvider == .claude {
                        privacyBullet("Anthropic 不會使用您的資料進行模型訓練")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }

            Spacer()

            // 按鈕
            VStack(spacing: 12) {
                Button {
                    onConsent(settings.llmProvider)
                    dismiss()
                } label: {
                    Text("同意並繼續")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.reclipGlass(tint: .accentColor))
                .controlSize(.large)

                Button("稍後設定") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 480, height: 680)
    }

    private func privacyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)

            Text(text)
                .font(.callout)
        }
    }
}

// MARK: - AI Option Card

struct AIOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let badge: String
    let badgeColor: Color
    let privacyNote: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 圖示
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 48, height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                    }

                // 內容
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(badge)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(badgeColor.opacity(0.2))
                            .foregroundStyle(badgeColor)
                            .clipShape(Capsule())
                    }

                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(privacyNote)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .primary : .tertiary)
                }

                // 選中指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Consent Manager

/// AI 同意管理器
@MainActor
public class AIConsentManager: ObservableObject {
    public static let shared = AIConsentManager()

    @AppStorage("ai.consentGiven")
    public var hasGivenConsent: Bool = false

    @AppStorage("ai.consentDate")
    private var consentDateString: String = ""

    public var consentDate: Date? {
        get {
            guard !consentDateString.isEmpty else { return nil }
            return ISO8601DateFormatter().date(from: consentDateString)
        }
        set {
            consentDateString = newValue.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        }
    }

    private init() {}

    /// 記錄使用者同意
    public func recordConsent(provider: LLMProviderType) {
        hasGivenConsent = true
        consentDate = Date()

        // 記錄到分析（如果有的話）
        // Analytics.log("ai_consent_given", provider: provider.rawValue)
    }

    /// 撤銷同意
    public func revokeConsent() {
        hasGivenConsent = false
        consentDateString = ""
    }
}

// MARK: - View Modifier

/// 確保 AI 同意的 View Modifier
struct EnsureAIConsentModifier: ViewModifier {
    @StateObject private var consentManager = AIConsentManager.shared
    @State private var showConsentSheet = false

    let onConsent: (LLMProviderType) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !consentManager.hasGivenConsent {
                    showConsentSheet = true
                }
            }
            .sheet(isPresented: $showConsentSheet) {
                AIConsentView { provider in
                    consentManager.recordConsent(provider: provider)
                    onConsent(provider)
                }
            }
    }
}

extension View {
    /// 確保使用者已同意 AI 資料處理
    public func ensureAIConsent(
        onConsent: @escaping (LLMProviderType) -> Void = { _ in }
    ) -> some View {
        modifier(EnsureAIConsentModifier(onConsent: onConsent))
    }
}

// MARK: - Preview

#Preview {
    AIConsentView { provider in
        print("Selected: \(provider)")
    }
}
