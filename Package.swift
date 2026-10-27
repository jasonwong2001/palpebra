// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Palpebra",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Palpebra", targets: ["Palpebra"])
    ],
    targets: [
        .target(
            name: "PalpebraCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Palpebra",
            dependencies: ["PalpebraCore"],
            path: "Sources/Palpebra",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PalpebraCoreTests",
            dependencies: ["PalpebraCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PalpebraTests",
            dependencies: ["Palpebra", "PalpebraCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
