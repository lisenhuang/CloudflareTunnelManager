// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudflareTunnelManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CloudflareTunnelManager", targets: ["CloudflareTunnelManager"])
    ],
    targets: [
        .executableTarget(
            name: "CloudflareTunnelManager",
            path: "Sources/CloudflareTunnelManager",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
