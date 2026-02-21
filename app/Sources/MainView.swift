import SwiftUI

struct MainView: View {
    @ObservedObject var scanner: ProjectScanner
    @StateObject private var prefs = Preferences.shared
    @State private var searchText = ""
    @State private var hasCheckedSetup = false
    private var filtered: [Project] {
        if searchText.isEmpty { return scanner.projects }
        return scanner.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var needsSetup: Bool { prefs.scanRoot.isEmpty }
    private var runningCount: Int { scanner.projects.filter(\.isRunning).count }

    var body: some View {
        VStack(spacing: 0) {
            mainContent
        }
        .frame(width: 380, height: 460)
        .background(PanelBackground())
        .preferredColorScheme(.dark)
        .onAppear {
            if needsSetup && !hasCheckedSetup {
                hasCheckedSetup = true
                SettingsWindow.open(prefs: prefs, scanner: scanner)
            }
            scanner.updateRoot(prefs.scanRoot)
            scanner.scan()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("devmux")
                    .font(Typo.title())
                    .foregroundColor(Palette.text)

                if runningCount > 0 {
                    Text("\(runningCount) session\(runningCount == 1 ? "" : "s")")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.running)
                        .padding(.leading, 4)
                }

                Spacer()

                headerButton(icon: "arrow.clockwise") { scanner.scan() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Palette.textMuted)
                    .font(.system(size: 11))
                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typo.body(13))
                    .foregroundColor(Palette.text)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Palette.textMuted)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.surface)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            // List
            if filtered.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { project in
                            ProjectRow(project: project) {
                                SessionManager.launch(project: project)
                            } onDetach: {
                                SessionManager.detach(project: project)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scanner.refreshStatus()
                                }
                            } onKill: {
                                SessionManager.kill(project: project)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scanner.refreshStatus()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            // Status bar
            statusBar
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            // Settings button
            Button { SettingsWindow.open(prefs: prefs, scanner: scanner) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Diagnostics toggle
            Button { DiagnosticWindow.shared.toggle() } label: {
                Image(systemName: "stethoscope")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DiagnosticWindow.shared.isVisible ? Palette.running : Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Toggle diagnostics")

            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5, height: 12)
                .padding(.horizontal, 8)

            // Config summary — keys dim, values white
            statusLine

            Spacer()

            // Quit
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Quit devmux")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Palette.surface.opacity(0.4))
    }

    private var statusLine: some View {
        HStack(spacing: 3) {
            statusPair("terminal", prefs.terminal.rawValue.lowercased())
            statusDot
            statusPair("mode", prefs.mode.rawValue)
            statusDot
            statusPair("home", "~/\((prefs.scanRoot as NSString).lastPathComponent)")
        }
    }

    private func statusPair(_ key: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(key + ":")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            Text(value)
                .font(Typo.mono(9))
                .foregroundColor(Palette.text)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(Palette.textMuted)
            .frame(width: 2, height: 2)
            .padding(.horizontal, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Palette.textMuted)

            Text("No projects yet")
                .font(Typo.heading(14))
                .foregroundColor(Palette.textDim)

            Text("Run  devmux init  in a project\nto add it here")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    // MARK: - Helpers

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textDim)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
