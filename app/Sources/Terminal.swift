import AppKit

enum Terminal: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm2 = "iTerm2"
    case warp = "Warp"
    case ghostty = "Ghostty"
    case kitty = "Kitty"
    case alacritty = "Alacritty"

    var id: String { rawValue }

    var bundleId: String {
        switch self {
        case .terminal:  return "com.apple.Terminal"
        case .iterm2:    return "com.googlecode.iterm2"
        case .warp:      return "dev.warp.Warp-Stable"
        case .ghostty:   return "com.mitchellh.ghostty"
        case .kitty:     return "net.kovidgoyal.kitty"
        case .alacritty: return "org.alacritty"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    static var installed: [Terminal] {
        allCases.filter(\.isInstalled)
    }

    /// Launch a command in this terminal
    func launch(command: String, in directory: String) {
        // Use single quotes for the shell command to avoid AppleScript escaping issues
        let dir = directory.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = command.replacingOccurrences(of: "'", with: "'\\''")
        let fullCmd = "cd '\(dir)' && \(cmd)"

        switch self {
        case .terminal:
            runOsascript(
                "tell application \"Terminal\"",
                "activate",
                "do script \"\(fullCmd)\"",
                "end tell"
            )

        case .iterm2:
            runOsascript(
                "tell application \"iTerm2\"",
                "activate",
                "set newWindow to (create window with default profile)",
                "tell current session of newWindow",
                "write text \"\(fullCmd)\"",
                "end tell",
                "end tell"
            )

        case .warp:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Warp", directory]
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                runOsascript(
                    "tell application \"System Events\"",
                    "tell process \"Warp\"",
                    "keystroke \"\(cmd)\"",
                    "keystroke return",
                    "end tell",
                    "end tell"
                )
            }

        case .ghostty:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", "Ghostty"]
            task.environment = ["GHOSTTY_SHELL_COMMAND": fullCmd]
            try? task.run()

        case .kitty:
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let kittyBin = appUrl.appendingPathComponent("Contents/MacOS/kitty").path
                let task = Process()
                task.executableURL = URL(fileURLWithPath: kittyBin)
                task.arguments = ["--single-instance", "--directory", directory, "sh", "-c", command]
                try? task.run()
            }

        case .alacritty:
            if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let bin = appUrl.appendingPathComponent("Contents/MacOS/alacritty").path
                let task = Process()
                task.executableURL = URL(fileURLWithPath: bin)
                task.arguments = ["--working-directory", directory, "-e", "sh", "-c", command]
                try? task.run()
            }
        }
    }

    /// The tag we put in the terminal window title via tmux set-titles
    static func windowTag(for session: String) -> String {
        "[devmux:\(session)]"
    }

    /// Find and focus the existing terminal window by its [devmux:name] tag, or open a new attach
    func focusOrAttach(session: String) {
        let tag = Terminal.windowTag(for: session)

        switch self {
        case .terminal:
            runOsascript(
                "tell application \"Terminal\"",
                "activate",
                "set found to false",
                "repeat with w in windows",
                "  if name of w contains \"\(tag)\" then",
                "    set index of w to 1",
                "    set found to true",
                "    exit repeat",
                "  end if",
                "end repeat",
                "if not found then do script \"tmux attach -t \(session)\"",
                "end tell"
            )

        case .iterm2:
            runOsascript(
                "tell application \"iTerm2\"",
                "activate",
                "set found to false",
                "repeat with w in windows",
                "  if name of w contains \"\(tag)\" then",
                "    select w",
                "    set found to true",
                "    exit repeat",
                "  end if",
                "end repeat",
                "if not found then",
                "  set newWindow to (create window with default profile)",
                "  tell current session of newWindow",
                "    write text \"tmux attach -t \(session)\"",
                "  end tell",
                "end if",
                "end tell"
            )

        default:
            // For terminals without good AppleScript support, just activate and attach
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", rawValue]
            try? task.run()
        }
    }
}

/// Run an AppleScript by joining lines into a single -e script block
private func runOsascript(_ lines: String...) {
    let script = lines.joined(separator: "\n")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
}
