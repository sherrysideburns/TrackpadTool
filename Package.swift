// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrackpadTool",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TrackpadTool",
            path: "Sources/TrackpadTool"
        )
    ]
)
