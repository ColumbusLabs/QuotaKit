// swift-tools-version: 6.2
import PackageDescription

/// QuotaKit Lite: a rate-limit-only Mac menu bar app (CodexBarMobile/Research/068-quotakit-lite-mac.md).
///
/// Deliberately separate from the root package: it never depends on `CodexBarCore`, so none of the full
/// app's heavy dependencies (cookies, QuickJS, cost scanning) are linked. The only shared code is the
/// iCloud sync layer, referenced through the symlink `QuotaKitLite/Shared -> ../Shared`.
let package = Package(
    name: "QuotaKitLite",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .target(
            name: "CodexBarSync",
            path: "Shared",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        // Foundation-only logic: models, parsers, pace, scheduling policy, envelope mapping (068 §13).
        .target(
            name: "LiteCore",
            dependencies: ["CodexBarSync"]),
        // The AppKit app. `Scripts/install.sh` wraps it in a signed `.app` with `App/Info.plist` and `Resources/`.
        .executableTarget(
            name: "QuotaKitLite",
            dependencies: ["LiteCore"]),
        .testTarget(
            name: "LiteCoreTests",
            dependencies: ["LiteCore"]),
    ])
