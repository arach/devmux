import AppKit
import CoreGraphics

// MARK: - Window Highlight Overlay

final class WindowHighlight {
    static let shared = WindowHighlight()

    private var overlayWindow: NSWindow?
    private var fadeTimer: Timer?

    /// Flash a green border overlay at the given screen frame
    func flash(frame: NSRect, duration: TimeInterval = 1.2) {
        dismiss()

        let inset: CGFloat = -8  // slightly larger than the window
        let expandedFrame = frame.insetBy(dx: inset, dy: inset)

        let window = NSWindow(
            contentRect: expandedFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let borderView = HighlightBorderView(frame: NSRect(origin: .zero, size: expandedFrame.size))
        window.contentView = borderView

        window.alphaValue = 0
        window.orderFrontRegardless()

        overlayWindow = window

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1.0
        }

        // Schedule fade out
        fadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }

    func dismiss() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    private func fadeOut() {
        guard let window = overlayWindow else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }
}

private class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let borderWidth: CGFloat = 4
        let cornerRadius: CGFloat = 12

        // Outer glow
        let glowRect = bounds.insetBy(dx: 1, dy: 1)
        let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: cornerRadius + 2, yRadius: cornerRadius + 2)
        glowPath.lineWidth = borderWidth + 4
        NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 0.15).setStroke()
        glowPath.stroke()

        // Main border
        let rect = bounds.insetBy(dx: borderWidth / 2 + 2, dy: borderWidth / 2 + 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = borderWidth
        NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 0.9).setStroke()
        path.stroke()
    }
}

enum TilePosition: String, CaseIterable, Identifiable {
    case left       = "left"
    case right      = "right"
    case topLeft    = "top-left"
    case topRight   = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case maximize   = "maximize"
    case center     = "center"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left:        return "Left"
        case .right:       return "Right"
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .maximize:    return "Max"
        case .center:      return "Center"
        }
    }

    var icon: String {
        switch self {
        case .left:        return "rectangle.lefthalf.filled"
        case .right:       return "rectangle.righthalf.filled"
        case .topLeft:     return "rectangle.inset.topleft.filled"
        case .topRight:    return "rectangle.inset.topright.filled"
        case .bottomLeft:  return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize:    return "rectangle.fill"
        case .center:      return "rectangle.center.inset.filled"
        }
    }

    /// Returns (x, y, w, h) as fractions of screen
    var rect: (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch self {
        case .left:        return (0,   0,   0.5, 1.0)
        case .right:       return (0.5, 0,   0.5, 1.0)
        case .topLeft:     return (0,   0,   0.5, 0.5)
        case .topRight:    return (0.5, 0,   0.5, 0.5)
        case .bottomLeft:  return (0,   0.5, 0.5, 0.5)
        case .bottomRight: return (0.5, 0.5, 0.5, 0.5)
        case .maximize:    return (0,   0,   1.0, 1.0)
        case .center:      return (0.15, 0.1, 0.7, 0.8)
        }
    }
}

// MARK: - Private CGS API for Spaces (loaded dynamically from SkyLight)

struct SpaceInfo: Identifiable {
    let id: Int      // CGS space ID
    let index: Int   // 1-based index within its display
    let display: Int // 0-based display index
    let isCurrent: Bool
}

struct DisplaySpaces {
    let displayIndex: Int
    let displayId: String
    let spaces: [SpaceInfo]
    let currentSpaceId: Int
}

private enum CGS {
    // Use Int32 for CGS connection IDs (C `int`), UInt64 for space IDs
    typealias MainConnectionIDFunc = @convention(c) () -> Int32
    typealias GetActiveSpaceFunc = @convention(c) (Int32) -> UInt64
    typealias CopyManagedDisplaySpacesFunc = @convention(c) (Int32) -> CFArray
    typealias CopySpacesForWindowsFunc = @convention(c) (Int32, Int32, CFArray) -> CFArray
    typealias SetCurrentSpaceFunc = @convention(c) (Int32, CFString, UInt64) -> Void

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static let mainConnectionID: MainConnectionIDFunc? = {
        guard let h = handle, let sym = dlsym(h, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnectionIDFunc.self)
    }()

    static let getActiveSpace: GetActiveSpaceFunc? = {
        guard let h = handle, let sym = dlsym(h, "CGSGetActiveSpace") else { return nil }
        return unsafeBitCast(sym, to: GetActiveSpaceFunc.self)
    }()

    static let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunc? = {
        guard let h = handle, let sym = dlsym(h, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(sym, to: CopyManagedDisplaySpacesFunc.self)
    }()

    static let copySpacesForWindows: CopySpacesForWindowsFunc? = {
        guard let h = handle, let sym = dlsym(h, "SLSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(sym, to: CopySpacesForWindowsFunc.self)
    }()

    static let setCurrentSpace: SetCurrentSpaceFunc? = {
        guard let h = handle, let sym = dlsym(h, "SLSManagedDisplaySetCurrentSpace") else { return nil }
        return unsafeBitCast(sym, to: SetCurrentSpaceFunc.self)
    }()
}

enum WindowTiler {
    /// Convert fractional rect to AppleScript bounds {left, top, right, bottom}
    /// AppleScript uses top-left origin; NSScreen uses bottom-left origin
    private static func appleScriptBounds(for position: TilePosition, screen: NSScreen? = nil) -> (Int, Int, Int, Int) {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen else { return (0, 0, 960, 540) }
        let full = targetScreen.frame
        let visible = targetScreen.visibleFrame

        let visTop = Int(full.height - visible.maxY)
        let visLeft = Int(visible.minX)
        let visW = Int(visible.width)
        let visH = Int(visible.height)

        let (fx, fy, fw, fh) = position.rect
        let x1 = visLeft + Int(CGFloat(visW) * fx)
        let y1 = visTop + Int(CGFloat(visH) * fy)
        let x2 = x1 + Int(CGFloat(visW) * fw)
        let y2 = y1 + Int(CGFloat(visH) * fh)
        return (x1, y1, x2, y2)
    }

    /// Tile a specific terminal window (found by devmux session tag) to a position
    static func tile(session: String, terminal: Terminal, to position: TilePosition) {
        let tag = Terminal.windowTag(for: session)
        let bounds = appleScriptBounds(for: position)

        switch terminal {
        case .terminal:
            tileAppleScript(app: "Terminal", tag: tag, bounds: bounds)
        case .iterm2:
            tileAppleScript(app: "iTerm2", tag: tag, bounds: bounds)
        default:
            tileFrontmost(bounds: bounds)
        }
    }

    /// Tile the frontmost window (works for any terminal)
    static func tileFrontmost(to position: TilePosition) {
        tileFrontmost(bounds: appleScriptBounds(for: position))
    }

    // MARK: - Spaces

    /// Get spaces organized by display
    static func getDisplaySpaces() -> [DisplaySpaces] {
        guard let mainConn = CGS.mainConnectionID,
              let copyManaged = CGS.copyManagedDisplaySpaces else { return [] }

        let cid = mainConn()
        guard let managed = copyManaged(cid) as? [[String: Any]] else { return [] }

        var result: [DisplaySpaces] = []
        for (displayIdx, display) in managed.enumerated() {
            let displayId = display["Display Identifier"] as? String ?? ""
            let rawSpaces = display["Spaces"] as? [[String: Any]] ?? []
            let currentDict = display["Current Space"] as? [String: Any]
            let currentId = currentDict?["id64"] as? Int ?? currentDict?["ManagedSpaceID"] as? Int ?? 0

            var spaces: [SpaceInfo] = []
            for (spaceIdx, space) in rawSpaces.enumerated() {
                let sid = space["id64"] as? Int ?? space["ManagedSpaceID"] as? Int ?? 0
                let type = space["type"] as? Int ?? 0
                if type == 0 {
                    spaces.append(SpaceInfo(
                        id: sid,
                        index: spaceIdx + 1,
                        display: displayIdx,
                        isCurrent: sid == currentId
                    ))
                }
            }

            result.append(DisplaySpaces(
                displayIndex: displayIdx,
                displayId: displayId,
                spaces: spaces,
                currentSpaceId: currentId
            ))
        }
        return result
    }

    /// Get the current active Space ID
    static func getCurrentSpace() -> Int {
        guard let mainConn = CGS.mainConnectionID, let getActive = CGS.getActiveSpace else { return 0 }
        return Int(getActive(mainConn()))
    }

    /// Find a window by its title tag and return its CGWindowID and owner PID
    static func findWindow(tag: String) -> (wid: UInt32, pid: pid_t)? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in windowList {
            if let name = info[kCGWindowName as String] as? String,
               name.contains(tag),
               let wid = info[kCGWindowNumber as String] as? UInt32,
               let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                return (wid, pid)
            }
        }
        return nil
    }

    /// Get the space ID(s) a window is on
    static func getSpacesForWindow(_ wid: UInt32) -> [Int] {
        guard let mainConn = CGS.mainConnectionID,
              let copySpaces = CGS.copySpacesForWindows else { return [] }
        let cid = mainConn()
        let arr = [NSNumber(value: wid)] as CFArray
        guard let result = copySpaces(cid, 0x7, arr) as? [NSNumber] else { return [] }
        return result.map { $0.intValue }
    }

    /// Switch a display to a specific Space
    static func switchToSpace(spaceId: Int) {
        guard let mainConn = CGS.mainConnectionID,
              let setSpace = CGS.setCurrentSpace else { return }

        let cid = mainConn()

        // Find which display this space belongs to
        let allDisplays = getDisplaySpaces()
        for display in allDisplays {
            if display.spaces.contains(where: { $0.id == spaceId }) {
                setSpace(cid, display.displayId as CFString, UInt64(spaceId))
                return
            }
        }
    }

    /// Navigate to a session's window: switch to its Space, raise it, highlight it
    /// Falls back through CG → AX → AppleScript depending on available permissions
    static func navigateToWindow(session: String, terminal: Terminal) {
        let diag = DiagnosticLog.shared
        let tag = Terminal.windowTag(for: session)
        diag.info("navigateToWindow: session=\(session) tag=\(tag) terminal=\(terminal.rawValue)")

        // Path 1: CG window lookup (needs Screen Recording permission for window names)
        if let (wid, pid) = findWindow(tag: tag) {
            diag.success("Path 1 (CG): found wid=\(wid) pid=\(pid)")
            navigateToKnownWindow(wid: wid, pid: pid, tag: tag, session: session, terminal: terminal)
            return
        }
        diag.warn("Path 1 (CG): findWindow failed — no Screen Recording?")

        // Path 2: AX API fallback (needs Accessibility permission)
        if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag) {
            diag.success("Path 2 (AX): found window for \(terminal.rawValue) pid=\(pid)")
            // Try to match AX window → CG window for space switching
            if let wid = matchCGWindow(pid: pid, axWindow: axWindow) {
                diag.success("Path 2 (AX→CG): matched CG wid=\(wid)")
                navigateToKnownWindow(wid: wid, pid: pid, tag: tag, session: session, terminal: terminal)
            } else {
                diag.warn("Path 2 (AX): no CG match — raising without space switch")
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate()
                }
                if let frame = axWindowFrame(axWindow) {
                    diag.info("Highlighting via AX frame: \(frame)")
                    DispatchQueue.main.async { WindowHighlight.shared.flash(frame: frame) }
                } else {
                    diag.error("axWindowFrame returned nil — no highlight")
                }
            }
            return
        }
        diag.warn("Path 2 (AX): findWindowViaAX failed — no Accessibility?")

        // Path 3: AppleScript / bare activate fallback
        diag.warn("Path 3: falling back to AppleScript/activate")
        activateViaAppleScript(session: session, tag: tag, terminal: terminal)
    }

    private static func navigateToKnownWindow(wid: UInt32, pid: pid_t, tag: String, session: String, terminal: Terminal) {
        let diag = DiagnosticLog.shared
        let windowSpaces = getSpacesForWindow(wid)
        let currentSpace = getCurrentSpace()
        diag.info("navigateToKnown: wid=\(wid) spaces=\(windowSpaces) current=\(currentSpace)")

        if let windowSpace = windowSpaces.first, windowSpace != currentSpace {
            diag.info("Switching from space \(currentSpace) → \(windowSpace)")
            switchToSpace(spaceId: windowSpace)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                raiseWindow(pid: pid, tag: tag, terminal: terminal)
                highlightWindow(session: session)
            }
        } else {
            diag.info("Window on current space — raising + highlighting")
            raiseWindow(pid: pid, tag: tag, terminal: terminal)
            highlightWindow(session: session)
        }
    }

    /// Find a terminal window by title tag using AX API (requires Accessibility permission)
    private static func findWindowViaAX(terminal: Terminal, tag: String) -> (pid: pid_t, window: AXUIElement)? {
        let diag = DiagnosticLog.shared
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == terminal.bundleId
        }) else {
            diag.error("findWindowViaAX: \(terminal.rawValue) (\(terminal.bundleId)) not running")
            return nil
        }

        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else {
            diag.error("findWindowViaAX: AX error \(err.rawValue) — Accessibility not granted?")
            return nil
        }

        diag.info("findWindowViaAX: \(windows.count) windows for \(terminal.rawValue), searching for \(tag)")
        for win in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? "<no title>"
            if title.contains(tag) {
                diag.success("findWindowViaAX: matched \"\(title)\"")
                return (pid, win)
            } else {
                diag.info("  skip: \"\(title)\"")
            }
        }
        diag.warn("findWindowViaAX: no window matched tag \(tag)")
        return nil
    }

    /// Match an AX window to its CG window ID using PID + bounds comparison
    private static func matchCGWindow(pid: pid_t, axWindow: AXUIElement) -> UInt32? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, let sv = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)

        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        for info in windowList {
            guard let wPid = info[kCGWindowOwnerPID as String] as? pid_t,
                  wPid == pid,
                  let wid = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var rect = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(boundsDict, &rect) {
                if abs(rect.origin.x - pos.x) < 2 && abs(rect.origin.y - pos.y) < 2 &&
                   abs(rect.width - size.width) < 2 && abs(rect.height - size.height) < 2 {
                    return wid
                }
            }
        }
        return nil
    }

    /// Get NSRect from an AX window element (AX uses top-left origin, convert to NS bottom-left)
    private static func axWindowFrame(_ window: AXUIElement) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard let pv = posRef, let sv = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)

        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryHeight = primaryScreen.frame.height
        return NSRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
    }

    /// Last-resort: use AppleScript for Terminal/iTerm2, or bare activate for others
    private static func activateViaAppleScript(session: String, tag: String, terminal: Terminal) {
        switch terminal {
        case .terminal:
            runScript("""
            tell application "Terminal"
                activate
                repeat with w in windows
                    if name of w contains "\(tag)" then
                        set index of w to 1
                        exit repeat
                    end if
                end repeat
            end tell
            """)
        case .iterm2:
            runScript("""
            tell application "iTerm2"
                activate
                repeat with w in windows
                    if name of w contains "\(tag)" then
                        select w
                        exit repeat
                    end if
                end repeat
            end tell
            """)
        default:
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == terminal.bundleId
            }) {
                app.activate()
            }
        }
    }

    /// Raise a specific window using AX API + AppleScript
    private static func raiseWindow(pid: pid_t, tag: String, terminal: Terminal) {
        let diag = DiagnosticLog.shared
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        var raised = false
        if err == .success, let windows = windowsRef as? [AXUIElement] {
            for win in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title.contains(tag) {
                    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                    diag.success("raiseWindow: raised \"\(title)\"")
                    raised = true
                    break
                }
            }
        }
        if !raised {
            diag.warn("raiseWindow: could not find window with tag \(tag) via AX (err=\(err.rawValue))")
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            diag.info("raiseWindow: activated \(app.localizedName ?? "pid:\(pid)")")
        }
    }

    // MARK: - Highlight

    /// Flash a highlight border around a session's terminal window
    static func highlightWindow(session: String) {
        let diag = DiagnosticLog.shared
        let tag = Terminal.windowTag(for: session)
        diag.info("highlightWindow: tag=\(tag)")

        // Path 1: CG approach (needs Screen Recording)
        if let (wid, _) = findWindow(tag: tag) {
            diag.info("highlight via CG: wid=\(wid)")
            guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
            for info in windowList {
                if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
                   let dict = info[kCGWindowBounds as String] as? NSDictionary {
                    var rect = CGRect.zero
                    if CGRectMakeWithDictionaryRepresentation(dict, &rect) {
                        guard let primaryScreen = NSScreen.screens.first else { return }
                        let primaryHeight = primaryScreen.frame.height
                        let nsRect = NSRect(
                            x: rect.origin.x,
                            y: primaryHeight - rect.origin.y - rect.height,
                            width: rect.width,
                            height: rect.height
                        )
                        diag.success("highlight CG flash at \(Int(nsRect.origin.x)),\(Int(nsRect.origin.y)) \(Int(nsRect.width))×\(Int(nsRect.height))")
                        DispatchQueue.main.async { WindowHighlight.shared.flash(frame: nsRect) }
                    }
                    return
                }
            }
            diag.warn("highlight CG: wid \(wid) not in window list")
            return
        }

        // Path 2: AX fallback — search installed terminals for the tagged window
        diag.info("highlight: CG failed, trying AX fallback across \(Terminal.installed.count) terminals")
        for terminal in Terminal.installed {
            if let (_, axWindow) = findWindowViaAX(terminal: terminal, tag: tag),
               let frame = axWindowFrame(axWindow) {
                diag.success("highlight AX flash at \(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))×\(Int(frame.height))")
                DispatchQueue.main.async { WindowHighlight.shared.flash(frame: frame) }
                return
            }
        }
        diag.error("highlight: no method found window — no highlight shown")
    }

    // MARK: - Private

    private static func tileAppleScript(app: String, tag: String, bounds: (Int, Int, Int, Int)) {
        let (x1, y1, x2, y2) = bounds
        let script = """
        tell application "\(app)"
            repeat with w in windows
                if name of w contains "\(tag)" then
                    set bounds of w to {\(x1), \(y1), \(x2), \(y2)}
                    set index of w to 1
                    exit repeat
                end if
            end repeat
        end tell
        """
        runScript(script)
    }

    private static func tileFrontmost(bounds: (Int, Int, Int, Int)) {
        let (x1, y1, x2, y2) = bounds
        let script = """
        tell application "System Events"
            set frontApp to name of first application process whose frontmost is true
        end tell
        tell application frontApp
            set bounds of front window to {\(x1), \(y1), \(x2), \(y2)}
        end tell
        """
        runScript(script)
    }

    private static func runScript(_ script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
