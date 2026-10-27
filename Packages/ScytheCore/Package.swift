// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScytheCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "ScytheCore", targets: ["ScytheCore"])
    ],
    targets: [
        .target(
            name: "ScytheCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScytheCoreTests",
            dependencies: ["ScytheCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
