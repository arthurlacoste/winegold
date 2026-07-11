// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinegoldNative",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "WinegoldCore",
            dependencies: ["CSQLite"]
        ),
        .target(
            name: "WinegoldUI",
            dependencies: ["WinegoldCore"]
        ),
        .executableTarget(
            name: "WinegoldNative",
            dependencies: ["WinegoldCore", "WinegoldUI"],
            exclude: ["WinegoldNative-Info.plist", "Resources"]
        ),
        .testTarget(
            name: "WinegoldNativeTests",
            dependencies: ["WinegoldCore", "WinegoldUI"]
        )
    ]
)
