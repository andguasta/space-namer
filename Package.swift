// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpaceNamer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SpaceNamer", path: "Sources/SpaceNamer")
    ]
)
