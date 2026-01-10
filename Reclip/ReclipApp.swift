import SwiftUI
import SwiftData
import ReclipCore
import ReclipUI

/// Reclip macOS 應用程式入口
@main
struct ReclipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(Project.modelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("匯入音訊...") {
                    NotificationCenter.default.post(name: .importAudio, object: nil)
                }
                .keyboardShortcut("o")
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("開始轉錄") {
                    NotificationCenter.default.post(name: .startTranscription, object: nil)
                }
                .keyboardShortcut("t")

                Button("開始分析") {
                    NotificationCenter.default.post(name: .startAnalysis, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("執行剪輯") {
                    NotificationCenter.default.post(name: .startEditing, object: nil)
                }
                .keyboardShortcut("e")
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let importAudio = Notification.Name("importAudio")
    static let startTranscription = Notification.Name("startTranscription")
    static let startAnalysis = Notification.Name("startAnalysis")
    static let startEditing = Notification.Name("startEditing")
}
