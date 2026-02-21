import AppKit
import SwiftUI

/// NSPanel subclass that accepts key events even without a titlebar
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CommandPaletteWindow {
    static let shared = CommandPaletteWindow()

    private var panel: NSPanel?
    private var scanner: ProjectScanner?

    func configure(scanner: ProjectScanner) {
        self.scanner = scanner
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let p = panel, p.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        // Always rebuild for fresh command state
        dismiss()

        guard let scanner = scanner else { return }

        // Ensure projects are up to date
        scanner.refreshStatus()

        let commands = CommandBuilder.build(scanner: scanner)
        let view = CommandPaletteView(commands: commands) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let hosting = NSHostingController(rootView: view)

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask: [.fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        // Center horizontally, slightly above vertical center (Spotlight-style)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 250
            let y = screenFrame.midY - 190 + (screenFrame.height * 0.1)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
