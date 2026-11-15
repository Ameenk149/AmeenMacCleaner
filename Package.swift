// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmeenMacCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AmeenMacCleaner", path: "Sources/AmeenMacCleaner")
    ]
)
