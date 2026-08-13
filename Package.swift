// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "dsh-app-swift",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "DshApp", targets: ["DshApp"])
    ],
    targets: [
        .executableTarget(
            name: "DshApp",
            path: "Sources/DshApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)
