// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CraftTasks",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CraftTasks",
            path: "Sources/CraftTasks"
        )
    ]
)
