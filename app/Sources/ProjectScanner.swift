import Foundation

class ProjectScanner: ObservableObject {
    @Published var projects: [Project] = []

    private let scanRoot: String

    init(root: String? = nil) {
        if let root { self.scanRoot = root }
        else {
            self.scanRoot = NSString("~/dev").expandingTildeInPath
        }
    }

    func scan() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: scanRoot) else { return }

        var found: [Project] = []

        for entry in entries.sorted() {
            let path = (scanRoot as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard !entry.hasPrefix(".") else { continue }

            let pType = detectType(at: path)
            let (devCmd, pm) = detectDevCommand(at: path)
            let config = readConfig(at: path)
            let paneCount = config ?? 2
            let hasConfig = config != nil
            let sName = entry.replacingOccurrences(
                of: "[^a-zA-Z0-9_-]", with: "-", options: .regularExpression
            )

            found.append(Project(
                id: entry,
                path: path,
                name: entry,
                devCommand: devCmd,
                packageManager: pm,
                projectType: pType,
                hasConfig: hasConfig,
                paneCount: paneCount,
                isRunning: isSessionRunning(sName)
            ))
        }

        DispatchQueue.main.async { self.projects = found }
    }

    func refreshStatus() {
        for i in projects.indices {
            projects[i].isRunning = isSessionRunning(projects[i].sessionName)
        }
    }

    // MARK: - Detection

    private func detectType(at path: String) -> ProjectType {
        let fm = FileManager.default
        let has = { (file: String) in fm.fileExists(atPath: (path as NSString).appendingPathComponent(file)) }
        if has("package.json") { return .node }
        if has("Package.swift") { return .swift }
        if has("Cargo.toml") { return .rust }
        if has("go.mod") { return .go }
        if has("pyproject.toml") || has("setup.py") || has("requirements.txt") { return .python }
        return .other
    }

    private func detectDevCommand(at path: String) -> (String?, String?) {
        let pkgPath = (path as NSString).appendingPathComponent("package.json")
        guard let data = FileManager.default.contents(atPath: pkgPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String]
        else { return (nil, nil) }

        let fm = FileManager.default
        let has = { (f: String) in fm.fileExists(atPath: (path as NSString).appendingPathComponent(f)) }

        var pm = "npm"
        if has("pnpm-lock.yaml") { pm = "pnpm" }
        else if has("bun.lockb") || has("bun.lock") { pm = "bun" }
        else if has("yarn.lock") { pm = "yarn" }

        let run = pm == "npm" ? "npm run" : pm
        if scripts["dev"] != nil { return ("\(run) dev", pm) }
        if scripts["start"] != nil { return ("\(run) start", pm) }
        if scripts["serve"] != nil { return ("\(run) serve", pm) }
        if scripts["watch"] != nil { return ("\(run) watch", pm) }
        return (nil, pm)
    }

    private func readConfig(at path: String) -> Int? {
        let configPath = (path as NSString).appendingPathComponent(".devmux.json")
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let panes = json["panes"] as? [[String: Any]]
        else { return nil }
        return panes.count
    }

    private func isSessionRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["tmux", "has-session", "-t", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
