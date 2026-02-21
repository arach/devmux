import SwiftUI

struct ProjectRow: View {
    let project: Project
    let onLaunch: () -> Void
    let onDetach: () -> Void
    let onKill: () -> Void
    let onSync: () -> Void
    let onRestart: (String?) -> Void

    @State private var isHovered = false
    @State private var showCoach = false
    @State private var showTilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Status bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(project.isRunning ? Palette.running : Palette.border)
                    .frame(width: 3, height: 32)

                // Info — tap to highlight window
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(Typo.heading(13))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)

                    if !project.paneSummary.isEmpty {
                        Text(project.paneSummary)
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                    } else if let cmd = project.devCommand {
                        Text(cmd)
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textMuted)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if project.isRunning {
                        WindowTiler.highlightWindow(session: project.sessionName)
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    if project.isRunning {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.15)) { showTilePicker.toggle() }
                            if !showTilePicker {
                                // Picker just opened — highlight the window
                                WindowTiler.highlightWindow(session: project.sessionName)
                            } else {
                                WindowHighlight.shared.dismiss()
                            }
                        }) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.system(size: 10))
                                .angularButton(Palette.textDim, filled: false)
                        }
                        .buttonStyle(.plain)

                        Button(action: { handleDetach() }) {
                            Text("Detach")
                                .angularButton(Palette.detach, filled: false)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onLaunch) {
                        Text(project.isRunning ? "Attach" : "Launch")
                            .angularButton(project.isRunning ? Palette.running : Palette.launch)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassCard(hovered: isHovered)

            // Coach card
            if showCoach {
                CoachView {
                    withAnimation(.easeOut(duration: 0.15)) { showCoach = false }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.top, 4)
            }

            // Tile picker
            if showTilePicker {
                TilePickerView(
                    sessionName: project.sessionName,
                    terminal: Preferences.shared.terminal,
                    onSelect: { position in
                        WindowHighlight.shared.dismiss()
                        WindowTiler.tile(
                            session: project.sessionName,
                            terminal: Preferences.shared.terminal,
                            to: position
                        )
                        withAnimation(.easeOut(duration: 0.15)) { showTilePicker = false }
                    },
                    onGoToSpace: { spaceId in
                        WindowHighlight.shared.dismiss()
                        WindowTiler.switchToSpace(spaceId: spaceId)
                        withAnimation(.easeOut(duration: 0.15)) { showTilePicker = false }
                    },
                    onDismiss: {
                        WindowHighlight.shared.dismiss()
                        withAnimation(.easeOut(duration: 0.15)) { showTilePicker = false }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if project.isRunning {
                Button("Attach") { onLaunch() }
                Button {
                    WindowTiler.navigateToWindow(
                        session: project.sessionName,
                        terminal: Preferences.shared.terminal
                    )
                } label: {
                    Label("Go to Window", systemImage: "macwindow")
                }
                Button("Detach") { onDetach() }
                Menu("Tile Window") {
                    ForEach(TilePosition.allCases) { tile in
                        Button {
                            WindowTiler.tile(
                                session: project.sessionName,
                                terminal: Preferences.shared.terminal,
                                to: tile
                            )
                        } label: {
                            Label(tile.label, systemImage: tile.icon)
                        }
                    }
                }
                Divider()
                Button("Sync Session") { onSync() }
                Menu("Restart Pane") {
                    ForEach(project.paneNames, id: \.self) { name in
                        Button(name) { onRestart(name) }
                    }
                }
                Divider()
                Button("Kill Session") { onKill() }
            } else {
                Button("Launch") { onLaunch() }
            }
        }
    }

    private func handleDetach() {
        if Preferences.shared.mode == .learning {
            withAnimation(.easeOut(duration: 0.15)) { showCoach.toggle() }
        } else {
            onDetach()
        }
    }
}

// MARK: - Coach view

struct CoachView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TMUX SHORTCUTS")
                    .font(Typo.pixel(12))
                    .foregroundColor(Palette.running)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textDim)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                        )
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                KeyCombo(keys: ["Ctrl+B", "D"], label: "Detach", color: Palette.detach)
                KeyCombo(keys: ["Ctrl+B", "X"], label: "Kill pane", color: Palette.kill)
                KeyCombo(keys: ["Ctrl+B", "\u{2190}\u{2192}"], label: "Switch pane", color: Palette.text)
            }

            Text("Session stays alive after detaching")
                .font(Typo.caption(10))
                .foregroundColor(Palette.textMuted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                )
        )
    }
}

struct KeyCombo: View {
    let keys: [String]
    let label: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(Typo.geistMonoBold(10))
                        .foregroundColor(Palette.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.bg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        )
                }
            }

            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(color)

            Spacer()
        }
    }
}
