import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            // The window follows the SwiftUI ideal size, so the form never
            // scrolls as sections appear/disappear (workspace picker, messages).
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "OpenCode Usage"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.minSize = NSSize(width: 540, height: 380)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("OpenCodeUsageSettingsWindow")
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
