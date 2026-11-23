// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mushaf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mushaf",
            path: "Sources/Mushaf",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
