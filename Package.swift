// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltoTranscription",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AltoTranscription", targets: ["AltoTranscription"])],
    targets: [
        .executableTarget(name: "AltoTranscription"),
        .testTarget(name: "AltoTranscriptionTests", dependencies: ["AltoTranscription"])
    ]
)
