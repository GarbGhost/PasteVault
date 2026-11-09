// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PasteVault",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PasteVault", targets: ["PasteVault"])
    ],
    targets: [
        .executableTarget(
            name: "PasteVault",
            path: "Sources/PasteVault",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security"),
                .linkedFramework("Vision"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "PasteVaultTests",
            dependencies: ["PasteVault"],
            path: "Tests/PasteVaultTests"
        )
    ]
)
