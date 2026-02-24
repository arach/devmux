import AppKit
import SwiftUI

/// NSPanel subclass that accepts key events even without a titlebar
private class CommandModePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CommandModeWindow {
    static let shared = CommandModeWindow()

    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let p = panel, p.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        // Always rebuild for fresh state
        dismiss()

        // Dismiss palette if visible
        if CommandPaletteWindow.shared.isVisible {
            CommandPaletteWindow.shared.dismiss()
        }

        let state = CommandModeState()
        state.onDismiss = { [weak self] in
            self?.dismiss()
        }
        state.onPanelResize = { [weak self] width, height in
            self?.animateResize(width: width, height: height)
        }
        state.enter()

        let view = CommandModeView(state: state)
            .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = CommandModePanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 360),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let cornerRadius: CGFloat = 14

        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.maskImage = Self.maskImage(cornerRadius: cornerRadius)

        panel.contentView = effectView

        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        // Center horizontally, slightly above vertical center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 290
            let y = screenFrame.midY - 180 + (screenFrame.height * 0.1)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    private func animateResize(width: CGFloat, height: CGFloat) {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        // Clamp to screen bounds with margin
        let newWidth = min(width, screenFrame.width * 0.92)
        let newHeight = min(height, screenFrame.height * 0.85)

        let newX = screenFrame.midX - newWidth / 2
        let newY = screenFrame.midY - newHeight / 2 + (screenFrame.height * 0.08)

        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Stretchable mask image for rounded corners
    private static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edgeLength = 2.0 * cornerRadius + 1.0
        let maskImage = NSImage(
            size: NSSize(width: edgeLength, height: edgeLength),
            flipped: false
        ) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.set()
            path.fill()
            return true
        }
        maskImage.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        maskImage.resizingMode = .stretch
        return maskImage
    }
}
