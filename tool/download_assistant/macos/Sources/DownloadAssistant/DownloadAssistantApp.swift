import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DownloadAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AssistantModel()

    var body: some Scene {
        WindowGroup("מסייע הורדה לאוצריא") {
            AssistantView(model: model)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(minWidth: 640, minHeight: 500)
        }
        .commands {
            // חלון אחד בלבד: "חלון חדש" היה פותח אשף שני על אותו מטמון.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
