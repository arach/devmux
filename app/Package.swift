// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevmuxApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DevmuxApp",
            path: "Sources"
        )
    ]
)
