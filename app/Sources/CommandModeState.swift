import AppKit
import Foundation

// MARK: - Phase

enum CommandModePhase: Equatable {
    case idle
    case inventory
    case desktopInventory
    case executing(String)
}

// MARK: - Inventory Snapshot

struct CommandModeInventory {
    struct Item {
        let name: String
        let group: String       // "Layer: X", "Group: Y", "Orphan"
        let status: Status
        let paneCount: Int
        let tileHint: String?   // "left", "right", etc.
    }
    enum Status { case running, attached, stopped }

    let activeLayer: String?
    let layerCount: Int
    let items: [Item]
}

// MARK: - Chord

struct Chord {
    let key: String         // display label e.g. "a", "1"
    let keyCode: UInt16
    let label: String       // e.g. "tile all"
    let action: () -> Void
}

// MARK: - Desktop Inventory Mode

enum DesktopInventoryMode: Equatable {
    case browsing
    case tiling
}

// MARK: - State Machine

final class CommandModeState: ObservableObject {
    @Published var phase: CommandModePhase = .idle
    @Published var inventory = CommandModeInventory(activeLayer: nil, layerCount: 0, items: [])
    @Published var chords: [Chord] = []
    @Published var desktopSnapshot: DesktopInventorySnapshot?
    @Published var selectedWindowId: UInt32?
    @Published var desktopMode: DesktopInventoryMode = .browsing

    var onDismiss: (() -> Void)?
    var onPanelResize: ((_ width: CGFloat, _ height: CGFloat) -> Void)?

    /// Compact panel size for chord view
    private let chordPanelSize: (CGFloat, CGFloat) = (580, 360)

    /// Compute desktop inventory panel size based on display count
    private var desktopPanelSize: (CGFloat, CGFloat) {
        let displayCount = max(1, desktopSnapshot?.displays.count ?? 1)
        let columnWidth: CGFloat = 480
        let dividers: CGFloat = CGFloat(displayCount - 1)
        let width = CGFloat(displayCount) * columnWidth + dividers + 32
        let height: CGFloat = 640
        return (width, height)
    }

    /// Flat window list for keyboard navigation
    var flatWindowList: [DesktopInventorySnapshot.InventoryWindowInfo] {
        desktopSnapshot?.allWindows ?? []
    }

    func enter() {
        inventory = buildInventory()
        chords = buildChords()
        phase = .inventory
    }

    /// Returns true if the key was consumed
    func handleKey(_ keyCode: UInt16) -> Bool {
        // Backtick (keyCode 50) toggles desktop inventory from either phase
        if keyCode == 50 {
            if phase == .desktopInventory {
                // Back to chord view
                selectedWindowId = nil
                desktopMode = .browsing
                phase = .inventory
                onPanelResize?(chordPanelSize.0, chordPanelSize.1)
                return true
            } else if phase == .inventory {
                // Enter desktop inventory
                let diag = DiagnosticLog.shared
                desktopSnapshot = buildDesktopInventory()
                selectedWindowId = nil
                desktopMode = .browsing
                phase = .desktopInventory
                let size = desktopPanelSize
                onPanelResize?(size.0, size.1)
                if let snap = desktopSnapshot {
                    let totalWindows = snap.allWindows.count
                    let totalSpaces = snap.displays.reduce(0) { $0 + $1.spaces.count }
                    diag.info("Desktop inventory: \(snap.displays.count) display(s), \(totalSpaces) space(s), \(totalWindows) window(s)")
                }
                return true
            }
        }

        // Route desktop inventory keys
        if phase == .desktopInventory {
            return handleDesktopInventoryKey(keyCode)
        }

        // Escape from chord view → dismiss
        if keyCode == 53 {
            dismiss()
            return true
        }

        guard phase == .inventory else { return false }

        // Check chord map
        if let chord = chords.first(where: { $0.keyCode == keyCode }) {
            phase = .executing(chord.label)
            let action = chord.action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                action()
                self?.dismiss()
            }
            return true
        }

        // Unknown key — ignore
        return true
    }

    // MARK: - Desktop Inventory Key Handling

    private func handleDesktopInventoryKey(_ keyCode: UInt16) -> Bool {
        if desktopMode == .tiling {
            return handleTilingKey(keyCode)
        }
        return handleBrowsingKey(keyCode)
    }

    private func handleBrowsingKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: // Escape → back to chord view
            selectedWindowId = nil
            desktopMode = .browsing
            phase = .inventory
            onPanelResize?(chordPanelSize.0, chordPanelSize.1)
            return true

        case 126, 38: // ↑ or j (keyCode 38 = j, 126 = up arrow)
            // j should go down, up arrow goes up
            if keyCode == 38 {
                moveSelection(by: 1)  // j = down
            } else {
                moveSelection(by: -1) // ↑ = up
            }
            return true

        case 125, 40: // ↓ or k (keyCode 40 = k, 125 = down arrow)
            // k should go up, down arrow goes down
            if keyCode == 40 {
                moveSelection(by: -1) // k = up
            } else {
                moveSelection(by: 1)  // ↓ = down
            }
            return true

        case 36, 3: // Return (36) or f (3) → focus selected window
            focusSelectedWindow()
            return true

        case 17: // t → enter tiling sub-mode
            if selectedWindowId != nil {
                desktopMode = .tiling
            }
            return true

        case 4: // h → highlight selected window
            highlightSelectedWindow()
            return true

        default:
            return true // consume all keys in desktop inventory
        }
    }

    private func handleTilingKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: // Escape → back to browsing
            desktopMode = .browsing
            return true

        case 123: // ← → tile left
            tileSelectedWindow(to: .left)
            return true

        case 124: // → → tile right
            tileSelectedWindow(to: .right)
            return true

        case 126: // ↑ → maximize
            tileSelectedWindow(to: .maximize)
            return true

        case 18: // 1 → top-left
            tileSelectedWindow(to: .topLeft)
            return true

        case 19: // 2 → top-right
            tileSelectedWindow(to: .topRight)
            return true

        case 20: // 3 → bottom-left
            tileSelectedWindow(to: .bottomLeft)
            return true

        case 21: // 4 → bottom-right
            tileSelectedWindow(to: .bottomRight)
            return true

        case 8: // c → center
            tileSelectedWindow(to: .center)
            return true

        default:
            return true // consume all keys
        }
    }

    // MARK: - Selection Actions

    private func moveSelection(by delta: Int) {
        let windows = flatWindowList
        guard !windows.isEmpty else { return }

        if let currentId = selectedWindowId,
           let currentIdx = windows.firstIndex(where: { $0.id == currentId }) {
            let newIdx = max(0, min(windows.count - 1, currentIdx + delta))
            selectedWindowId = windows[newIdx].id
        } else {
            selectedWindowId = delta > 0 ? windows.first?.id : windows.last?.id
        }

        if let wid = selectedWindowId, let win = windows.first(where: { $0.id == wid }) {
            let title = win.title.isEmpty ? "(untitled)" : String(win.title.prefix(30))
            DiagnosticLog.shared.info("Select: wid=\(wid) \"\(title)\"")
        }
    }

    private func focusSelectedWindow() {
        guard let wid = selectedWindowId,
              let window = flatWindowList.first(where: { $0.id == wid }) else { return }

        DiagnosticLog.shared.info("Focus: wid=\(wid) pid=\(window.pid)")
        let pid = window.pid
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WindowTiler.navigateToWindowById(wid: wid, pid: pid)
        }
    }

    private func highlightSelectedWindow() {
        guard let wid = selectedWindowId else { return }
        DiagnosticLog.shared.info("Highlight: wid=\(wid)")
        WindowTiler.highlightWindowById(wid: wid)
    }

    private func tileSelectedWindow(to position: TilePosition) {
        guard let wid = selectedWindowId,
              let window = flatWindowList.first(where: { $0.id == wid }) else { return }

        DiagnosticLog.shared.info("Tile: wid=\(wid) → \(position.rawValue)")
        WindowTiler.tileWindowById(wid: wid, pid: window.pid, to: position)
        desktopMode = .browsing

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.desktopSnapshot = self?.buildDesktopInventory()
        }
    }

    func dismiss() {
        phase = .idle
        onDismiss?()
    }

    // MARK: - Inventory Builder

    private func buildInventory() -> CommandModeInventory {
        let workspace = WorkspaceManager.shared
        let tmux = TmuxModel.shared
        let inventoryMgr = InventoryManager.shared

        // Refresh inventory so orphans are current
        inventoryMgr.refresh()

        let activeLayer = workspace.activeLayer
        let layerCount = workspace.config?.layers?.count ?? 0

        var items: [CommandModeInventory.Item] = []

        // Active layer projects
        if let layer = activeLayer {
            for lp in layer.projects {
                if let groupId = lp.group, let group = workspace.group(byId: groupId) {
                    let running = workspace.isGroupRunning(group)
                    let paneCount = group.tabs.count
                    items.append(.init(
                        name: group.label,
                        group: "Layer: \(layer.label)",
                        status: running ? .running : .stopped,
                        paneCount: paneCount,
                        tileHint: lp.tile
                    ))
                } else if let path = lp.path {
                    let name = (path as NSString).lastPathComponent
                    let sessionName = WorkspaceManager.sessionName(for: path)
                    let session = tmux.sessions.first(where: { $0.name == sessionName })
                    let status: CommandModeInventory.Status
                    if let s = session {
                        status = s.attached ? .attached : .running
                    } else {
                        status = .stopped
                    }
                    items.append(.init(
                        name: name,
                        group: "Layer: \(layer.label)",
                        status: status,
                        paneCount: session?.panes.count ?? 0,
                        tileHint: lp.tile
                    ))
                }
            }
        }

        // Tab groups not in active layer
        if let groups = workspace.config?.groups {
            let layerGroupIds = Set(activeLayer?.projects.compactMap(\.group) ?? [])
            for group in groups where !layerGroupIds.contains(group.id) {
                let running = workspace.isGroupRunning(group)
                items.append(.init(
                    name: group.label,
                    group: "Group: \(group.label)",
                    status: running ? .running : .stopped,
                    paneCount: group.tabs.count,
                    tileHint: nil
                ))
            }
        }

        // Orphans
        for orphan in inventoryMgr.orphans {
            items.append(.init(
                name: orphan.name,
                group: "Orphan",
                status: orphan.attached ? .attached : .running,
                paneCount: orphan.panes.count,
                tileHint: nil
            ))
        }

        return CommandModeInventory(
            activeLayer: activeLayer?.label,
            layerCount: layerCount,
            items: items
        )
    }

    // MARK: - Desktop Inventory Builder

    private func buildDesktopInventory() -> DesktopInventorySnapshot {
        let screens = NSScreen.screens
        let displaySpaces = WindowTiler.getDisplaySpaces()
        let primaryHeight = screens.first?.frame.height ?? 0

        // Build space-to-display mapping: spaceId → (displayIndex, spaceIndex)
        var spaceToDisplay: [Int: (displayIdx: Int, spaceIdx: Int)] = [:]
        for (dIdx, ds) in displaySpaces.enumerated() {
            for space in ds.spaces {
                spaceToDisplay[space.id] = (dIdx, space.index)
            }
        }

        // Current space IDs per display
        let currentSpaceIds = Set(displaySpaces.map(\.currentSpaceId))

        // Query ALL windows (not just on-screen) to capture every space
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return DesktopInventorySnapshot(displays: [], timestamp: Date())
        }

        // Parse raw CG window info
        struct RawWindow {
            let wid: UInt32; let app: String; let pid: Int32
            let title: String; let frame: WindowFrame
            let devmuxSession: String?; let spaceIds: [Int]
        }

        // System/helper processes that create layer-0 windows users don't care about
        let blockedApps: Set<String> = [
            // macOS system
            "WindowServer", "Dock", "SystemUIServer", "Control Center",
            "Notification Center", "NotificationCenter", "Spotlight", "WindowManager",
            "TextInputMenuAgent", "TextInputSwitcher", "universalAccessAuthWarn",
            "AXVisualSupportAgent", "loginwindow", "ScreenSaverEngine",
            // UI service helpers (run as XPC, show popover/autofill UI)
            "AutoFill", "AuthenticationServicesHelper", "CursorUIViewService",
            "SharedWebCredentialViewService", "CoreServicesUIAgent",
            "UserNotificationCenter", "SecurityAgent", "OSDUIHelper",
            "PassKit UIService", "QuickLookUIService", "ScopedBookmarkAgent",
            // Dev tool helpers
            "Instruments", "FileMerge",
        ]
        // Also block apps whose name ends with known helper suffixes
        let blockedSuffixes = ["UIService", "UIHelper", "Agent", "Helper", "ViewService"]

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let rawCount = rawList.count

        var allWindows: [RawWindow] = []
        for info in rawList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { continue }

            // Skip our own windows
            guard pid != ownPid else { continue }

            // Skip known system/helper processes
            guard !blockedApps.contains(ownerName) else { continue }
            if blockedSuffixes.contains(where: { ownerName.hasSuffix($0) }) { continue }

            var rect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &rect),
                  rect.width >= 100, rect.height >= 50 else { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let spaceIds = WindowTiler.getSpacesForWindow(wid)

            // Skip windows not assigned to any space (background helpers)
            guard !spaceIds.isEmpty else { continue }

            // For windows on a current space, require them to be actually visible.
            // This filters hidden helper windows (AutoFill, CursorUIViewService, etc.)
            // while keeping real windows on other spaces.
            let isOnCurrentSpace = spaceIds.contains(where: { currentSpaceIds.contains($0) })
            if isOnCurrentSpace && !isOnScreen { continue }

            let frame = WindowFrame(x: Double(rect.origin.x), y: Double(rect.origin.y),
                                    w: Double(rect.width), h: Double(rect.height))

            var devmuxSession: String?
            if let range = title.range(of: #"\[devmux:([^\]]+)\]"#, options: .regularExpression) {
                let match = String(title[range])
                devmuxSession = String(match.dropFirst(8).dropLast(1))
            }

            allWindows.append(RawWindow(wid: wid, app: ownerName, pid: pid, title: title,
                                        frame: frame, devmuxSession: devmuxSession, spaceIds: spaceIds))
        }

        DiagnosticLog.shared.info("Desktop scan: \(rawCount) raw → \(allWindows.count) after filter")

        // Assign each window to (display, space)
        struct AssignedWindow {
            let win: RawWindow; let displayIdx: Int; let spaceId: Int; let spaceIdx: Int; let isOnScreen: Bool
        }

        var assigned: [AssignedWindow] = []
        for win in allWindows {
            // Primary: use space→display mapping
            for sid in win.spaceIds {
                if let mapping = spaceToDisplay[sid] {
                    assigned.append(AssignedWindow(
                        win: win,
                        displayIdx: mapping.displayIdx,
                        spaceId: sid,
                        spaceIdx: mapping.spaceIdx,
                        isOnScreen: currentSpaceIds.contains(sid)
                    ))
                    break  // assign to first known space
                }
            }

            // Fallback: match by frame center (no space info)
            if !win.spaceIds.contains(where: { spaceToDisplay[$0] != nil }) {
                let cx = win.frame.x + win.frame.w / 2
                let cy = win.frame.y + win.frame.h / 2
                let nsCy = primaryHeight - cy
                for (sIdx, screen) in screens.enumerated() {
                    if screen.frame.contains(NSPoint(x: cx, y: nsCy)) {
                        let ds = sIdx < displaySpaces.count ? displaySpaces[sIdx] : nil
                        let currentSid = ds?.currentSpaceId ?? 0
                        let currentIdx = ds?.spaces.first(where: { $0.isCurrent })?.index ?? 1
                        assigned.append(AssignedWindow(
                            win: win, displayIdx: sIdx,
                            spaceId: currentSid, spaceIdx: currentIdx, isOnScreen: true
                        ))
                        break
                    }
                }
            }
        }

        // Build hierarchical: Display → Space → App → Windows
        var displays: [DesktopInventorySnapshot.DisplayInfo] = []

        for (screenIdx, screen) in screens.enumerated() {
            let frame = screen.frame
            let visible = screen.visibleFrame
            let name = screen.localizedName

            let ds = screenIdx < displaySpaces.count ? displaySpaces[screenIdx] : nil
            let spaceCount = ds?.spaces.count ?? 1
            let currentSpaceIdx = ds?.spaces.first(where: { $0.isCurrent })?.index ?? 1

            let screenWindows = assigned.filter { $0.displayIdx == screenIdx }

            // Group by space
            var windowsBySpace: [Int: [AssignedWindow]] = [:]
            for aw in screenWindows {
                windowsBySpace[aw.spaceId, default: []].append(aw)
            }

            // Build SpaceGroups sorted by space index
            var spaceGroups: [DesktopInventorySnapshot.SpaceGroup] = []
            let allSpacesForDisplay = ds?.spaces ?? []

            for spaceInfo in allSpacesForDisplay {
                let spaceWindows = windowsBySpace[spaceInfo.id] ?? []
                guard !spaceWindows.isEmpty else { continue }

                // Group by app within space
                var appGroups: [String: [AssignedWindow]] = [:]
                for aw in spaceWindows {
                    appGroups[aw.win.app, default: []].append(aw)
                }

                var groups: [DesktopInventorySnapshot.AppGroup] = []
                for appName in appGroups.keys.sorted() {
                    let wins = appGroups[appName]!
                    let inventoryWindows = wins.map { aw -> DesktopInventorySnapshot.InventoryWindowInfo in
                        let tile = aw.isOnScreen ? WindowTiler.inferTilePosition(frame: aw.win.frame, screen: screen) : nil
                        return DesktopInventorySnapshot.InventoryWindowInfo(
                            id: aw.win.wid,
                            pid: aw.win.pid,
                            title: aw.win.title,
                            frame: aw.win.frame,
                            tilePosition: tile,
                            isDevmux: aw.win.devmuxSession != nil,
                            devmuxSession: aw.win.devmuxSession,
                            spaceIndex: aw.spaceIdx,
                            isOnScreen: aw.isOnScreen
                        )
                    }
                    groups.append(DesktopInventorySnapshot.AppGroup(
                        id: "\(spaceInfo.id)-\(appName)",
                        appName: appName,
                        windows: inventoryWindows
                    ))
                }

                spaceGroups.append(DesktopInventorySnapshot.SpaceGroup(
                    id: spaceInfo.id,
                    index: spaceInfo.index,
                    isCurrent: spaceInfo.isCurrent,
                    apps: groups
                ))
            }

            let isMain = screen == NSScreen.main
            displays.append(DesktopInventorySnapshot.DisplayInfo(
                id: ds?.displayId ?? "display-\(screenIdx)",
                name: name,
                resolution: (w: Int(frame.width), h: Int(frame.height)),
                visibleFrame: (w: Int(visible.width), h: Int(visible.height)),
                isMain: isMain,
                spaceCount: spaceCount,
                currentSpaceIndex: currentSpaceIdx,
                spaces: spaceGroups
            ))
        }

        return DesktopInventorySnapshot(displays: displays, timestamp: Date())
    }

    // MARK: - Chord Map

    private func buildChords() -> [Chord] {
        let workspace = WorkspaceManager.shared

        var chords: [Chord] = []

        // [a] tile all — re-tile active layer's windows
        chords.append(Chord(key: "a", keyCode: 0, label: "tile all") {
            WorkspaceManager.shared.retileCurrentLayer()
        })

        // [s] split — tile two most recent left/right
        chords.append(Chord(key: "s", keyCode: 1, label: "split") {
            let running = ProjectScanner.shared.projects.filter(\.isRunning)
            let term = Preferences.shared.terminal
            if running.count >= 2 {
                WindowTiler.tile(session: running[0].sessionName, terminal: term, to: .left)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    WindowTiler.tile(session: running[1].sessionName, terminal: term, to: .right)
                }
            } else if running.count == 1 {
                WindowTiler.tile(session: running[0].sessionName, terminal: term, to: .maximize)
            }
        })

        // [m] maximize — maximize frontmost terminal
        chords.append(Chord(key: "m", keyCode: 46, label: "maximize") {
            let term = Preferences.shared.terminal
            // Find frontmost running project
            let running = ProjectScanner.shared.projects.filter(\.isRunning)
            if let first = running.first {
                WindowTiler.tile(session: first.sessionName, terminal: term, to: .maximize)
            }
        })

        // [1]-[3] layer switching (dynamic)
        let layers = workspace.config?.layers ?? []
        let layerKeyCodes: [UInt16] = [18, 19, 20]  // 1, 2, 3
        for (i, layer) in layers.prefix(3).enumerated() {
            let idx = i
            chords.append(Chord(key: "\(i + 1)", keyCode: layerKeyCodes[i], label: layer.label.lowercased()) {
                WorkspaceManager.shared.switchToLayer(index: idx)
            })
        }

        // [r] refresh
        chords.append(Chord(key: "r", keyCode: 15, label: "refresh") {
            ProjectScanner.shared.scan()
            TmuxModel.shared.poll()
            InventoryManager.shared.refresh()
        })

        // [p] palette
        chords.append(Chord(key: "p", keyCode: 35, label: "palette") {
            CommandPaletteWindow.shared.show()
        })

        return chords
    }
}
