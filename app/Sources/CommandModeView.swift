import SwiftUI
import AppKit

struct CommandModeView: View {
    @ObservedObject var state: CommandModeState
    @State private var eventMonitor: Any?
    @State private var hoveredWindowId: UInt32?

    private var isDesktopInventory: Bool {
        state.phase == .desktopInventory
    }

    private static let columnWidth: CGFloat = 480

    private var panelWidth: CGFloat {
        if isDesktopInventory {
            let displayCount = max(1, state.desktopSnapshot?.displays.count ?? 1)
            let dividers = CGFloat(displayCount - 1)
            return CGFloat(displayCount) * Self.columnWidth + dividers + 32
        }
        return 580
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if isDesktopInventory {
                desktopInventoryContent
            } else {
                inventoryGrid
            }
            divider
            chordFooter
        }
        .frame(width: panelWidth)
        .background(Palette.bg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.borderLit, lineWidth: 0.5)
        )
        .overlay(executingOverlay)
        .onAppear { installKeyHandler() }
        .onDisappear { removeKeyHandler() }
        .animation(.easeInOut(duration: 0.2), value: isDesktopInventory)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isDesktopInventory ? "DESKTOP INVENTORY" : "COMMAND MODE")
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)

            if isDesktopInventory {
                Button(action: { state.copyInventoryToClipboard() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(Typo.mono(9))
                    }
                    .foregroundColor(Palette.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let layer = state.inventory.activeLayer {
                HStack(spacing: 4) {
                    Text("Layer: \(layer)")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.running)

                    Text("[\(state.inventory.layerCount > 0 ? "\(WorkspaceManager.shared.activeLayerIndex + 1)/\(state.inventory.layerCount)" : "—")]")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.running.opacity(0.10))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Inventory Grid

    private var inventoryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let grouped = groupedItems
                if grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped, id: \.0) { section, items in
                        sectionHeader(section)
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            inventoryRow(item)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minHeight: 160, maxHeight: 240)
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No sessions found")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Desktop Inventory Content

    private var desktopInventoryContent: some View {
        Group {
            if let snapshot = state.desktopSnapshot, !snapshot.displays.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(snapshot.displays.enumerated()), id: \.element.id) { idx, display in
                        if idx > 0 {
                            Rectangle()
                                .fill(Palette.border)
                                .frame(width: 0.5)
                        }
                        displayColumn(display)
                            .frame(width: Self.columnWidth)
                    }
                }
            } else {
                desktopEmptyState
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func displayColumn(_ display: DesktopInventorySnapshot.DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            displayHeader(display)
            divider

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(display.spaces) { space in
                            spaceHeader(space, display: display)
                            columnHeaders
                            ForEach(space.apps) { appGroup in
                                appGroupRows(appGroup, dimmed: !space.isCurrent)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.selectedWindowId) { newId in
                    // Only scroll if the selected window is in this display
                    guard let id = newId else { return }
                    let displayWindows = display.spaces.flatMap { $0.apps.flatMap { $0.windows } }
                    if displayWindows.contains(where: { $0.id == id }) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var desktopEmptyState: some View {
        HStack {
            Spacer()
            Text("No windows found")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
            Spacer()
        }
        .padding(.vertical, 24)
    }

    private func displayHeader(_ display: DesktopInventorySnapshot.DisplayInfo) -> some View {
        HStack(spacing: 6) {
            Text(display.name)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
            Text("\(display.visibleFrame.w)×\(display.visibleFrame.h)")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textDim)
            Spacer()
            Text("\(display.spaceCount) space\(display.spaceCount == 1 ? "" : "s")")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func spaceHeader(_ space: DesktopInventorySnapshot.SpaceGroup, display: DesktopInventorySnapshot.DisplayInfo) -> some View {
        HStack(spacing: 5) {
            Text("Space \(space.index)")
                .font(Typo.monoBold(10))
                .foregroundColor(space.isCurrent ? Palette.running : Palette.textDim)
            if space.isCurrent {
                Text("active")
                    .font(Typo.mono(8))
                    .foregroundColor(Palette.running.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.running.opacity(0.10))
                    )
            }
            Spacer()
            let windowCount = space.apps.reduce(0) { $0 + $1.windows.count }
            Text("\(windowCount)")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("APP / WINDOW")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE")
                .frame(width: 90, alignment: .leading)
            Text("TILE")
                .frame(width: 70, alignment: .trailing)
        }
        .font(Typo.mono(9))
        .foregroundColor(Palette.textMuted)
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private func appGroupRows(_ appGroup: DesktopInventorySnapshot.AppGroup, dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if appGroup.windows.count == 1, let win = appGroup.windows.first {
                singleWindowRow(app: appGroup.appName, window: win)
            } else {
                Text(appGroup.appName)
                    .font(Typo.monoBold(10))
                    .foregroundColor(dimmed ? Palette.textDim : Palette.text)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 1)
                ForEach(appGroup.windows) { win in
                    windowRow(win, indented: true)
                }
            }
        }
        .opacity(dimmed ? 0.6 : 1.0)
    }

    private func singleWindowRow(app: String, window: DesktopInventorySnapshot.InventoryWindowInfo) -> some View {
        let isSelected = state.selectedWindowId == window.id
        let isHovered = hoveredWindowId == window.id

        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(window.isDevmux ? "●" : "•")
                    .font(.system(size: 7))
                    .foregroundColor(window.isDevmux ? Palette.running : (isSelected ? Palette.text : Palette.textDim))
                Text(app)
                    .font(Typo.monoBold(10))
                    .foregroundColor(window.isDevmux ? Palette.running : Palette.text)
                Text(windowTitle(window))
                    .font(Typo.mono(10))
                    .foregroundColor(window.isDevmux ? Palette.running.opacity(isSelected ? 1.0 : 0.7) : (isSelected ? Palette.text : Palette.textDim))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(sizeText(window.frame))
                .font(Typo.mono(10))
                .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                .frame(width: 90, alignment: .leading)

            Text(window.tilePosition?.label ?? "\u{2014}")
                .font(Typo.mono(10))
                .foregroundColor(window.tilePosition != nil ? (isSelected ? Palette.text : Palette.textDim) : Palette.textMuted)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Palette.surface : (isHovered ? Palette.surface.opacity(0.5) : Color.clear))
                .padding(.horizontal, 6)
        )
        .overlay(
            isSelected ?
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                    .padding(.horizontal, 6)
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectedWindowId = window.id }
        .onHover { hovering in hoveredWindowId = hovering ? window.id : nil }
        .id(window.id)
    }

    private func windowRow(_ window: DesktopInventorySnapshot.InventoryWindowInfo, indented: Bool) -> some View {
        let isSelected = state.selectedWindowId == window.id
        let isHovered = hoveredWindowId == window.id

        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                if indented {
                    Text(" ")
                        .font(Typo.mono(10))
                }
                Text(window.isDevmux ? "●" : "•")
                    .font(.system(size: 7))
                    .foregroundColor(window.isDevmux ? Palette.running : (isSelected ? Palette.text : Palette.textDim))
                Text(windowTitle(window))
                    .font(Typo.mono(10))
                    .foregroundColor(window.isDevmux ? Palette.running : (isSelected ? Palette.text : Palette.textDim))
                    .lineLimit(1)
                if window.isDevmux, let session = window.devmuxSession {
                    Text("[\(session)]")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running.opacity(isSelected ? 1.0 : 0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(sizeText(window.frame))
                .font(Typo.mono(10))
                .foregroundColor(isSelected ? Palette.text : Palette.textDim)
                .frame(width: 90, alignment: .leading)

            Text(window.tilePosition?.label ?? "\u{2014}")
                .font(Typo.mono(10))
                .foregroundColor(window.tilePosition != nil ? (isSelected ? Palette.text : Palette.textDim) : Palette.textMuted)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Palette.surface : (isHovered ? Palette.surface.opacity(0.5) : Color.clear))
                .padding(.horizontal, 6)
        )
        .overlay(
            isSelected ?
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                    .padding(.horizontal, 6)
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectedWindowId = window.id }
        .onHover { hovering in hoveredWindowId = hovering ? window.id : nil }
        .id(window.id)
    }

    private func windowTitle(_ window: DesktopInventorySnapshot.InventoryWindowInfo) -> String {
        let title = window.title
        if title.isEmpty { return "(untitled)" }
        if title.count > 30 {
            return String(title.prefix(27)) + "..."
        }
        return title
    }

    private func sizeText(_ frame: WindowFrame) -> String {
        "\(Int(frame.w))×\(Int(frame.h))"
    }

    /// Group items by their group label
    private var groupedItems: [(String, [CommandModeInventory.Item])] {
        var result: [(String, [CommandModeInventory.Item])] = []
        var seen = Set<String>()
        for item in state.inventory.items {
            if !seen.contains(item.group) {
                seen.insert(item.group)
                result.append((item.group, state.inventory.items.filter { $0.group == item.group }))
            }
        }
        return result
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.mono(9))
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func inventoryRow(_ item: CommandModeInventory.Item) -> some View {
        HStack(spacing: 0) {
            // Name
            Text(item.name)
                .font(Typo.mono(11))
                .foregroundColor(statusColor(item.status))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Pane count
            Text(item.paneCount > 0 ? "\(item.paneCount) pane\(item.paneCount == 1 ? "" : "s")" : "—")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textDim)
                .frame(width: 70, alignment: .leading)

            // Status dot + label
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(item.status))
                    .frame(width: 5, height: 5)
                Text(statusLabel(item.status))
                    .font(Typo.mono(10))
                    .foregroundColor(statusColor(item.status))
            }
            .frame(width: 80, alignment: .leading)

            // Tile hint
            Text(item.tileHint ?? "\u{2014}")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .frame(width: 60, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    private func statusColor(_ status: CommandModeInventory.Status) -> Color {
        switch status {
        case .running: return Palette.running
        case .attached: return Palette.running
        case .stopped: return Palette.textMuted
        }
    }

    private func statusLabel(_ status: CommandModeInventory.Status) -> String {
        switch status {
        case .running: return "running"
        case .attached: return "attached"
        case .stopped: return "stopped"
        }
    }

    // MARK: - Chord Footer

    private var chordFooter: some View {
        VStack(spacing: 4) {
            if isDesktopInventory && state.desktopMode == .tiling {
                // Tiling sub-mode hints
                HStack(spacing: 12) {
                    chordHint(key: "←", label: "left")
                    chordHint(key: "→", label: "right")
                    chordHint(key: "↑", label: "max")
                    chordHint(key: "1-4", label: "quadrants")
                    chordHint(key: "c", label: "center")
                    chordHint(key: "esc", label: "back")
                    Spacer()
                }
            } else if isDesktopInventory && state.desktopMode == .actions {
                // Action mode hints
                HStack(spacing: 12) {
                    chordHint(key: "↩", label: "focus")
                    chordHint(key: "t", label: "tile")
                    chordHint(key: "h", label: "highlight")
                    chordHint(key: "esc", label: "back")
                    Spacer()
                }
            } else if isDesktopInventory && state.selectedWindowId != nil {
                // Selection active — browsing hints
                HStack(spacing: 12) {
                    chordHint(key: "↑↓", label: "navigate")
                    chordHint(key: "←→", label: "display")
                    chordHint(key: "↩", label: "actions")
                    chordHint(key: "`", label: "chords")
                    chordHint(key: "esc", label: "deselect")
                    Spacer()
                }
            } else if isDesktopInventory {
                // No selection — browsing hints
                HStack(spacing: 12) {
                    chordHint(key: "↑↓", label: "navigate")
                    chordHint(key: "←→", label: "display")
                    chordHint(key: "`", label: "chords")
                    chordHint(key: "esc", label: "back")
                    Spacer()
                }
            } else {
                // First row: action chords
                HStack(spacing: 12) {
                    chordHint(key: "`", label: "desktop")
                    ForEach(state.chords.prefix(3), id: \.key) { chord in
                        chordHint(key: chord.key, label: chord.label)
                    }
                    Spacer()
                }

                // Second row: layer chords + utility
                HStack(spacing: 12) {
                    ForEach(state.chords.dropFirst(3), id: \.key) { chord in
                        chordHint(key: chord.key, label: chord.label)
                    }
                    chordHint(key: "esc", label: "dismiss")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.surface.opacity(0.4))
    }

    private func chordHint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Typo.mono(9))
                .foregroundColor(Palette.text)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
            Text(label)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
    }

    // MARK: - Executing Overlay

    @ViewBuilder
    private var executingOverlay: some View {
        if case .executing(let label) = state.phase {
            ZStack {
                Palette.bg.opacity(0.85)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Palette.running)
                    Text(label)
                        .font(Typo.monoBold(13))
                        .foregroundColor(Palette.running)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity)
        }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }

    // MARK: - Key Handler

    private func installKeyHandler() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard state.phase == .inventory || state.phase == .desktopInventory else { return event }
            let consumed = state.handleKey(event.keyCode)
            return consumed ? nil : event
        }
    }

    // Clear hover when leaving desktop inventory
    private func clearDesktopState() {
        hoveredWindowId = nil
    }

    private func removeKeyHandler() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
