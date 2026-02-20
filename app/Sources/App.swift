import SwiftUI

@main
struct DevmuxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = ProjectScanner()

    var body: some Scene {
        MenuBarExtra("Devmux", systemImage: "terminal") {
            MainView(scanner: scanner)
        }
        .menuBarExtraStyle(.window)
    }
}
