// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BodyAndSoul",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BodyAndSoul", targets: ["BodyAndSoul"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "BodyAndSoul",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "BodyAndSoulTests", dependencies: ["BodyAndSoul"])
    ]
)
