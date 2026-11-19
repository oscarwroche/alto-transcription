// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltoTranscription",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AltoTranscription", targets: ["AltoTranscription"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "AltoTranscription",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "AltoTranscriptionTests", dependencies: ["AltoTranscription"])
    ]
)
