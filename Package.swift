// swift-tools-version: 6.0
import PackageDescription

// NintekKit — shared foundation for Enzo's native apps (Cairn first, then
// ShopKeep, Tare, …). Deliberately dependency-free: the HTTP + auth-token
// seams are protocols, so platform SDKs like MSAL live in the app target and
// this package stays buildable and testable headlessly on any platform.
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
    ],
    targets: [
        .target(name: "NintekKit"),
        .testTarget(name: "NintekKitTests", dependencies: ["NintekKit"]),
    ]
)
