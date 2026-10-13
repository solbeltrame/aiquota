// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIquota",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIquota", targets: ["AIquota"]),
    ],
    dependencies: [
        // Official Zstandard library (BSD). Needed to read the Claude app's zstd-encoded usage cache.
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7"),
        // Sparkle powers signed, in-app updates for the public macOS release.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6"),
    ],
    targets: [
        // Data model, provider adapters, refresh + alert logic. No AppKit.
        .target(name: "AIquotaCore", dependencies: [.product(name: "libzstd", package: "zstd")]),
        // AppKit drawing of the compact menu bar indicators (testable without an app).
        .target(name: "AIquotaUI", dependencies: ["AIquotaCore"]),
        // The app: status items, popover, settings, onboarding, notifications.
        .executableTarget(name: "AIquota", dependencies: [
            "AIquotaCore", "AIquotaUI", .product(name: "Sparkle", package: "Sparkle"),
        ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "AIquotaCoreTests", dependencies: ["AIquotaCore", .product(name: "libzstd", package: "zstd")],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "AIquotaUITests", dependencies: ["AIquotaUI", "AIquotaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
