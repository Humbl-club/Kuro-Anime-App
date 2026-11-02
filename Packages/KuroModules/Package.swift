// swift-tools-version: 6.2
import PackageDescription

// Isolation and language policy for every target (explicit; nothing is inherited from the
// app's build settings):
// - Swift language mode 5 (the app is Swift 5; no language upgrade as part of extraction).
// - Default isolation is nonisolated. Value types are declared `Sendable`; stores are
//   annotated `@MainActor` explicitly. The app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
//   does not apply here.
// - Complete strict-concurrency checking (diagnostics are warnings in Swift 5 mode and are
//   kept at zero) and `MemberImportVisibility` (explicit imports, as in the app).
let isolationPolicy: [SwiftSetting] = [
    .defaultIsolation(nil),
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "KuroModules",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KuroCore", targets: ["KuroCore"]),
        .library(name: "KuroLibrary", targets: ["KuroLibrary"]),
        .library(name: "KuroSupabase", targets: ["KuroSupabase"]),
    ],
    targets: [
        // Foundation-only identity and account-scoping contracts.
        .target(name: "KuroCore", swiftSettings: isolationPolicy),
        // Tracking domain: values, contracts and the authoritative LibraryStore.
        .target(
            name: "KuroLibrary",
            dependencies: ["KuroCore"],
            swiftSettings: isolationPolicy,
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // List-table adapter. No SDK import: the app binds `LibraryRowTransport` to supabase-swift.
        .target(name: "KuroSupabase", dependencies: ["KuroCore", "KuroLibrary"], swiftSettings: isolationPolicy),
        .testTarget(name: "KuroCoreTests", dependencies: ["KuroCore"], swiftSettings: isolationPolicy),
        .testTarget(name: "KuroLibraryTests", dependencies: ["KuroCore", "KuroLibrary"], swiftSettings: isolationPolicy),
        .testTarget(
            name: "KuroSupabaseTests",
            dependencies: ["KuroCore", "KuroLibrary", "KuroSupabase"],
            swiftSettings: isolationPolicy
        ),
    ],
    swiftLanguageModes: [.v5]
)
