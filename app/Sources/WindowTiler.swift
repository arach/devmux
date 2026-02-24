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

    // Move windows between spaces
    typealias AddWindowsToSpacesFunc = @convention(c) (Int32, CFArray, CFArray) -> Void
    typealias RemoveWindowsFromSpacesFunc = @convention(c) (Int32, CFArray, CFArray) -> Void

    static let addWindowsToSpaces: AddWindowsToSpacesFunc? = {
        guard let h = handle else { return nil }
        guard let sym = dlsym(h, "CGSAddWindowsToSpaces") ?? dlsym(h, "SLSAddWindowsToSpaces") else { return nil }
        return unsafeBitCast(sym, to: AddWindowsToSpacesFunc.self)
    }()

    static let removeWindowsFromSpaces: RemoveWindowsFromSpacesFunc? = {
        guard let h = handle else { return nil }
        guard let sym = dlsym(h, "CGSRemoveWindowsFromSpaces") ?? dlsym(h, "SLSRemoveWindowsFromSpaces") else { return nil }
        return unsafeBitCast(sym, to: RemoveWindowsFromSpacesFunc.self)
    }()
}

enum WindowTiler {
    /// Whether CGS move-between-spaces APIs are available
    static var canMoveWindowsBetweenSpaces: Bool {
        CGS.addWindowsToSpaces != nil && CGS.removeWindowsFromSpaces != nil
    }

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

    // MARK: - Move Window Between Spaces

    enum MoveResult {
        case success(method: String)
        case alreadyOnSpace
        case windowNotFound
        case failed(reason: String)
    }

    /// Move a session's terminal window to a different Space.
    /// Note: On macOS 14.5+ the CGS move APIs are silently denied.
    /// When that happens we fall back to just switching the user's view.
    static func moveWindowToSpace(session: String, terminal: Terminal, spaceId: Int) -> MoveResult {
        let diag = DiagnosticLog.shared
        let tag = Terminal.windowTag(for: session)
        diag.info("moveWindowToSpace: session=\(session) tag=\(tag) targetSpace=\(spaceId)")

        // Find the window — CG first, then AX→CG fallback
        let wid: UInt32
        if let (w, _) = findWindow(tag: tag) {
            wid = w
            diag.info("moveWindowToSpace: found via CG wid=\(w)")
        } else if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag),
                  let w = matchCGWindow(pid: pid, axWindow: axWindow) {
            wid = w
            diag.info("moveWindowToSpace: found via AX→CG wid=\(w)")
        } else {
            diag.warn("moveWindowToSpace: window not found for tag \(tag) — switching view only")
            switchToSpace(spaceId: spaceId)
            return .windowNotFound
        }

        // Check current spaces
        let currentSpaces = getSpacesForWindow(wid)
        diag.info("moveWindowToSpace: wid=\(wid) currentSpaces=\(currentSpaces)")
        if currentSpaces.contains(spaceId) {
            diag.info("moveWindowToSpace: already on target space — switching view")
            switchToSpace(spaceId: spaceId)
            return .alreadyOnSpace
        }

        // Try CGS direct move (works on older macOS, silently denied on 14.5+)
        if let result = moveViaCGS(wid: wid, fromSpaces: currentSpaces, toSpace: spaceId) {
            return result
        }

        // CGS unavailable — just switch the user's view
        diag.info("moveWindowToSpace: CGS unavailable, switching view to space")
        switchToSpace(spaceId: spaceId)
        return .success(method: "switch-view")
    }

    /// Attempt CGS-based window move. Returns nil if APIs are unavailable.
    private static func moveViaCGS(wid: UInt32, fromSpaces: [Int], toSpace: Int) -> MoveResult? {
        let diag = DiagnosticLog.shared
        guard let mainConn = CGS.mainConnectionID,
              let addToSpaces = CGS.addWindowsToSpaces,
              let removeFromSpaces = CGS.removeWindowsFromSpaces else {
            return nil
        }

        let cid = mainConn()
        let windowArray = [NSNumber(value: wid)] as CFArray
        let targetArray = [NSNumber(value: toSpace)] as CFArray

        addToSpaces(cid, windowArray, targetArray)
        if !fromSpaces.isEmpty {
            let sourceArray = fromSpaces.map { NSNumber(value: $0) } as CFArray
            removeFromSpaces(cid, windowArray, sourceArray)
        }

        // Verify the move took effect (macOS 14.5+ silently denies)
        let newSpaces = getSpacesForWindow(wid)
        if newSpaces.contains(toSpace) && !fromSpaces.allSatisfy({ newSpaces.contains($0) }) {
            diag.success("moveViaCGS: successfully moved wid=\(wid) to space \(toSpace)")
            return .success(method: "CGS")
        }

        // CGS was silently denied — switch the view instead
        diag.warn("moveViaCGS: silently denied (macOS 14.5+ restriction) — switching view")
        switchToSpace(spaceId: toSpace)
        return .success(method: "switch-view")
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

    // MARK: - Window Info

    struct WindowInfo {
        let spaceIndex: Int           // 1-based space number
        let displayIndex: Int         // 0-based display index
        let tilePosition: TilePosition?  // inferred from bounds, nil if free-form
        let wid: UInt32
    }

    /// Get spatial info for a session's terminal window (space, display, tile position)
    static func getWindowInfo(session: String, terminal: Terminal) -> WindowInfo? {
        let tag = Terminal.windowTag(for: session)

        // Find the window
        let wid: UInt32
        if let (w, _) = findWindow(tag: tag) {
            wid = w
        } else if let (pid, axWindow) = findWindowViaAX(terminal: terminal, tag: tag),
                  let w = matchCGWindow(pid: pid, axWindow: axWindow) {
            wid = w
        } else {
            return nil
        }

        // Determine which space/display the window is on
        let windowSpaces = getSpacesForWindow(wid)
        let allDisplays = getDisplaySpaces()

        var spaceIndex = 1
        var displayIndex = 0

        if let windowSpaceId = windowSpaces.first {
            for display in allDisplays {
                if let space = display.spaces.first(where: { $0.id == windowSpaceId }) {
                    spaceIndex = space.index
                    displayIndex = display.displayIndex
                    break
                }
            }
        }

        let tile = inferTilePosition(wid: wid)

        return WindowInfo(
            spaceIndex: spaceIndex,
            displayIndex: displayIndex,
            tilePosition: tile,
            wid: wid
        )
    }

    /// Infer tile position from a window frame + screen without re-querying CGWindowList
    static func inferTilePosition(frame: WindowFrame, screen: NSScreen) -> TilePosition? {
        let visible = screen.visibleFrame
        let full = screen.frame

        // CG top-left origin → visible frame top-left origin
        let primaryHeight = NSScreen.screens.first?.frame.height ?? full.height
        let visTop = primaryHeight - visible.maxY
        let fx = (frame.x - visible.origin.x) / visible.width
        let fy = (frame.y - visTop) / visible.height
        let fw = frame.w / visible.width
        let fh = frame.h / visible.height

        let tolerance: CGFloat = 0.05

        for position in TilePosition.allCases {
            let (px, py, pw, ph) = position.rect
            if abs(fx - CGFloat(px)) < tolerance && abs(fy - CGFloat(py)) < tolerance &&
               abs(fw - CGFloat(pw)) < tolerance && abs(fh - CGFloat(ph)) < tolerance {
                return position
            }
        }
        return nil
    }

    /// Infer tile position from a window's current bounds relative to its screen
    private static func inferTilePosition(wid: UInt32) -> TilePosition? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the window's bounds
        var windowRect = CGRect.zero
        for info in windowList {
            if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
               let dict = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(dict, &windowRect)
                break
            }
        }
        guard windowRect.width > 0 else { return nil }

        // Find which screen contains the window center
        let centerX = windowRect.midX
        let centerY = windowRect.midY
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryHeight = primaryScreen.frame.height

        // CG uses top-left origin; convert to NS bottom-left for screen matching
        let nsCenterY = primaryHeight - centerY

        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: centerX, y: nsCenterY))
        }) ?? NSScreen.main ?? primaryScreen

        let visible = screen.visibleFrame
        let full = screen.frame

        // Convert CG rect to fractional coordinates relative to visible frame
        // CG top-left origin → visible frame top-left origin
        let visTop = full.height - visible.maxY + full.origin.y
        let fx = (windowRect.origin.x - visible.origin.x) / visible.width
        let fy = (windowRect.origin.y - visTop) / visible.height
        let fw = windowRect.width / visible.width
        let fh = windowRect.height / visible.height

        let tolerance: CGFloat = 0.05

        for position in TilePosition.allCases {
            let (px, py, pw, ph) = position.rect
            if abs(fx - px) < tolerance && abs(fy - py) < tolerance &&
               abs(fw - pw) < tolerance && abs(fh - ph) < tolerance {
                return position
            }
        }

        return nil
    }

    // MARK: - By-ID Window Operations (Desktop Inventory)

    /// Navigate to an arbitrary window by its CG window ID: switch space, raise, highlight
    static func navigateToWindowById(wid: UInt32, pid: Int32) {
        let diag = DiagnosticLog.shared
        diag.info("navigateToWindowById: wid=\(wid) pid=\(pid)")

        // Switch to window's space if needed
        let windowSpaces = getSpacesForWindow(wid)
        let currentSpace = getCurrentSpace()

        if let windowSpace = windowSpaces.first, windowSpace != currentSpace {
            diag.info("Switching from space \(currentSpace) → \(windowSpace)")
            switchToSpace(spaceId: windowSpace)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                raiseWindowById(wid: wid, pid: pid)
                highlightWindowById(wid: wid)
            }
        } else {
            raiseWindowById(wid: wid, pid: pid)
            highlightWindowById(wid: wid)
        }
    }

    /// Flash a highlight border on any window by its CG window ID
    static func highlightWindowById(wid: UInt32) {
        guard let frame = cgWindowFrame(wid: wid) else {
            DiagnosticLog.shared.warn("highlightWindowById: no frame for wid=\(wid)")
            return
        }
        DispatchQueue.main.async { WindowHighlight.shared.flash(frame: frame) }
    }

    /// Tile any window by its CG window ID to a position using AX API
    static func tileWindowById(wid: UInt32, pid: Int32, to position: TilePosition) {
        let diag = DiagnosticLog.shared
        diag.info("tileWindowById: wid=\(wid) pid=\(pid) pos=\(position.rawValue)")

        // Find the screen the window is on
        guard let windowFrame = cgWindowFrame(wid: wid) else {
            diag.warn("tileWindowById: no frame for wid=\(wid)")
            return
        }
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSPoint(x: windowFrame.midX, y: windowFrame.midY))
        }) ?? NSScreen.main ?? NSScreen.screens[0]

        let visible = screen.visibleFrame
        let (fx, fy, fw, fh) = position.rect

        // Calculate target in NS coordinates (bottom-left origin)
        let targetX = visible.origin.x + visible.width * fx
        let targetY = visible.origin.y + visible.height * (1.0 - fy - fh)
        let targetW = visible.width * fw
        let targetH = visible.height * fh

        // Convert NS bottom-left → AX top-left origin
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        let axX = targetX
        let axY = primaryHeight - targetY - targetH

        // Find the AX window matching this CG wid by frame comparison
        guard let axWindow = findAXWindowByFrame(wid: wid, pid: pid) else {
            diag.warn("tileWindowById: couldn't match AX window for wid=\(wid)")
            return
        }

        // Set position and size via AX
        var newPos = CGPoint(x: axX, y: axY)
        var newSize = CGSize(width: targetW, height: targetH)

        if let posValue = AXValueCreate(.cgPoint, &newPos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        }

        diag.success("tileWindowById: tiled wid=\(wid) to \(position.rawValue)")
    }

    /// Get NSRect (bottom-left origin) for a known CG window ID
    private static func cgWindowFrame(wid: UInt32) -> NSRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windowList {
            if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
               let dict = info[kCGWindowBounds as String] as? NSDictionary {
                var rect = CGRect.zero
                if CGRectMakeWithDictionaryRepresentation(dict, &rect) {
                    guard let primaryScreen = NSScreen.screens.first else { return nil }
                    let primaryHeight = primaryScreen.frame.height
                    return NSRect(
                        x: rect.origin.x,
                        y: primaryHeight - rect.origin.y - rect.height,
                        width: rect.width,
                        height: rect.height
                    )
                }
            }
        }
        return nil
    }

    /// Raise a window by matching its CG window ID to an AX element via frame comparison
    private static func raiseWindowById(wid: UInt32, pid: Int32) {
        let diag = DiagnosticLog.shared

        if let axWindow = findAXWindowByFrame(wid: wid, pid: pid) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            diag.success("raiseWindowById: raised wid=\(wid)")
        } else {
            diag.warn("raiseWindowById: couldn't match AX window for wid=\(wid)")
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    /// Find the AX window element for a given CG window ID by matching frames
    private static func findAXWindowByFrame(wid: UInt32, pid: Int32) -> AXUIElement? {
        // Get CG frame for the window
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        var cgRect = CGRect.zero
        for info in windowList {
            if let num = info[kCGWindowNumber as String] as? UInt32, num == wid,
               let dict = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(dict, &cgRect)
                break
            }
        }
        guard cgRect.width > 0 else { return nil }

        // Find AX window with matching frame
        let appRef = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for win in windows {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
            guard let pv = posRef, let sv = sizeRef else { continue }

            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sv as! AXValue, .cgSize, &size)

            if abs(cgRect.origin.x - pos.x) < 2 && abs(cgRect.origin.y - pos.y) < 2 &&
               abs(cgRect.width - size.width) < 2 && abs(cgRect.height - size.height) < 2 {
                return win
            }
        }
        return nil
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
