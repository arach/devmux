import Foundation

struct Project: Identifiable {
    let id: String
    let path: String
    let name: String
    let devCommand: String?
    let packageManager: String?
    let projectType: ProjectType
    let hasConfig: Bool
    let paneCount: Int
    var isRunning: Bool

    var sessionName: String {
        name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
    }
}

enum ProjectType: String {
    case node = "node"
    case swift = "swift"
    case rust = "rust"
    case go = "go"
    case python = "py"
    case other = ""

    var color: String {
        switch self {
        case .node: return "green"
        case .swift: return "orange"
        case .rust: return "red"
        case .go: return "cyan"
        case .python: return "yellow"
        case .other: return "gray"
        }
    }
}
