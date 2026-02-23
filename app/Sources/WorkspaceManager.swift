import CryptoKit
import Foundation

// MARK: - Data Model

struct LayerProject: Codable {
    let path: String
    let tile: String?
}

struct Layer: Codable, Identifiable {
    let id: String
    let label: String
    let projects: [LayerProject]
}

struct WorkspaceConfig: Codable {
    let name: String
    let layers: [Layer]
}

// MARK: - Manager

class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var config: WorkspaceConfig?
    @Published var activeLayerIndex: Int = 0
    @Published var isSwitching: Bool = false

    private let configPath: String
    private let activeLayerKey = "devmux.activeLayerIndex"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = (home as NSString).appendingPathComponent(".devmux/workspace.json")
        self.activeLayerIndex = UserDefaults.standard.integer(forKey: activeLayerKey)
        loadConfig()
    }

    var activeLayer: Layer? {
        guard let config, activeLayerIndex < config.layers.count else { return nil }
        return config.layers[activeLayerIndex]
    }

    // MARK: - Config I/O

    func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath),
              let data = FileManager.default.contents(atPath: configPath) else {
            config = nil
            return
        }
        do {
            config = try JSONDecoder().decode(WorkspaceConfig.self, from: data)
            // Clamp saved index
            if let config, activeLayerIndex >= config.layers.count {
                activeLayerIndex = 0
            }
        } catch {
            DiagnosticLog.shared.error("WorkspaceManager: failed to decode workspace.json — \(error.localizedDescription)")
            config = nil
        }
    }

    func reloadConfig() {
        loadConfig()
    }

    // MARK: - Layer Switching

    func switchToLayer(index: Int) {
        guard let config, index < config.layers.count, index != activeLayerIndex else { return }

        let diag = DiagnosticLog.shared
        diag.info("WorkspaceManager: switching from layer \(activeLayerIndex) to \(index)")

        isSwitching = true
        let terminal = Preferences.shared.terminal
        let scanner = ProjectScanner.shared
        let targetLayer = config.layers[index]

        // For each project in the target layer: launch if needed, then focus + tile
        for (i, lp) in targetLayer.projects.enumerated() {
            let sessionName = Self.sessionName(for: lp.path)
            let project = scanner.projects.first(where: { $0.path == lp.path })

            if let project, project.isRunning {
                // Already running — just navigate to its window (raises + focuses)
                diag.info("  focus: \(project.name)")
                WindowTiler.navigateToWindow(session: sessionName, terminal: terminal)
            } else if let project {
                // Not running — launch it
                diag.info("  launch: \(project.name)")
                SessionManager.launch(project: project)
            } else {
                // Not in scanner — launch directly
                diag.info("  launch (direct): \(sessionName)")
                terminal.launch(command: "/opt/homebrew/bin/devmux", in: lp.path)
            }

            // Tile to configured position after a staggered delay
            if let tileStr = lp.tile, let position = TilePosition(rawValue: tileStr) {
                let delay = Double(i) * 0.3 + (project?.isRunning == true ? 0.2 : 0.8)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    diag.info("  tile: \(sessionName) -> \(position.rawValue)")
                    WindowTiler.tile(session: sessionName, terminal: terminal, to: position)
                }
            }
        }

        // Update state
        activeLayerIndex = index
        UserDefaults.standard.set(index, forKey: activeLayerKey)

        // Refresh scanner status after windows settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            scanner.refreshStatus()
            self.isSwitching = false
        }
    }

    // MARK: - Session Name Helper

    /// Replicates Project.sessionName logic from a bare path
    static func sessionName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let base = name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let hash = SHA256.hash(data: Data(path.utf8))
        let short = hash.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(base)-\(short)"
    }
}
