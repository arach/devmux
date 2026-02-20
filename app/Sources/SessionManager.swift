import AppKit

enum SessionManager {
    /// Launch devmux for a project by opening Terminal and running the CLI
    static func launch(project: Project) {
        let escapedPath = project.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedPath)' && devmux"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    /// Kill a tmux session
    static func kill(project: Project) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["tmux", "kill-session", "-t", project.sessionName]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
