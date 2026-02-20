import Foundation

struct Project: Identifiable {
    let id: String
    let path: String
    let name: String
    let devCommand: String?
    let packageManager: String?
    let hasConfig: Bool
    let paneCount: Int
    let paneSummary: String
    var isRunning: Bool

    var sessionName: String {
        name.replacingOccurrences(
            of: "[^a-zA-Z0-9_-]",
            with: "-",
            options: .regularExpression
        )
    }
}
