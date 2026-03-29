// swift-tools-version: 6.0
import PackageDescription

let rustLibPath = "../target/aarch64-apple-darwin/release"
let sdkSystemLibs = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/system"

let rustLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-L" + rustLibPath, "-lcitadel_core", "-L" + sdkSystemLibs, "-lunwind"]),
]

let package = Package(
    name: "CitadelApp",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CitadelCore", targets: ["CitadelCore"]),
    ],
    targets: [
        // C module wrapping the Rust header
        .target(
            name: "CCitadelCore",
            path: "CCitadelCore",
            publicHeadersPath: "."
        ),
        // Swift wrapper library
        .target(
            name: "CitadelCore",
            dependencies: ["CCitadelCore"],
            path: "Sources",
            linkerSettings: rustLinkerSettings
        ),
        // macOS SwiftUI application
        .executableTarget(
            name: "Citadel",
            dependencies: ["CitadelCore"],
            path: "App",
            linkerSettings: rustLinkerSettings
        ),
        // Tests
        .testTarget(
            name: "CitadelTests",
            dependencies: ["CitadelCore"],
            path: "Tests",
            resources: [.copy("Resources")],
            linkerSettings: rustLinkerSettings
        ),
    ]
)
