import AppKit

/// Registers the global hotkey (Cmd+Shift+D) on launch.
/// The menu bar itself is handled by SwiftUI's MenuBarExtra.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        HotkeyManager.shared.register {
            // Toggle the MenuBarExtra by simulating a click on the status item
        }

        // Style the MenuBarExtra panel when it appears
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let panel = note.object as? NSPanel else { return }
            Self.stylePanel(panel)
        }
    }

    private static func stylePanel(_ panel: NSPanel) {
        let bg = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        panel.backgroundColor = bg
        panel.isOpaque = false
        panel.hasShadow = true
        panel.invalidateShadow()
    }
}
