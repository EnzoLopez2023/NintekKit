// swift-tools-version: 6.0
import PackageDescription

// NintekKit — dependency-free shared infrastructure for Enzo's native apps.
// Cairn links the local-only NintekKitCairn product; the original NintekKit
// product remains the source-compatible aggregate for existing consumers.
let package = Package(
    name: "NintekKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        // Tare's Watch app and its complications consume `TareWidgetSnapshot`
        // and `TareWatchLogEntry` from here, so the package has to build for the
        // wrist too. The ActivityKit and AppIntents sources are already behind
        // `#if os(iOS)` and stay out of the watchOS slice.
        .watchOS(.v10),
    ],
    products: [
        .library(name: "NintekKit", targets: ["NintekKit"]),
        .library(name: "NintekKitCairn", targets: ["NintekKitCairn"]),
    ],
    targets: [
        .target(
            name: "NintekKitCairn",
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
        .target(name: "NintekKit", dependencies: ["NintekKitCairn"]),
        .testTarget(name: "NintekKitCairnTests", dependencies: ["NintekKitCairn"]),
        .testTarget(name: "NintekKitTests", dependencies: ["NintekKit"]),
    ]
)
