// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pot",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PotCore", targets: ["PotCore"]), .executable(name: "Pot", targets: ["PotApp"]), .executable(name: "pot-dev", targets: ["PotDev"])],
    // Sparkle (MIT) is the only third-party runtime component: signed, opt-out update checks
    // for the macOS app (decision 31). PotCore and PotDev never depend on it.
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        // Vendored official Zstandard 1.5.7 single-file decoder (BSD). Decompression only; see Sources/CZstd/LICENSE.
        .target(name: "CZstd", exclude: ["LICENSE"], cSettings: [.define("ZSTD_DISABLE_ASM", to: "1")]),
        .target(name: "PotCore", dependencies: ["CSQLite", "CZstd"], resources: [.process("Resources")]),
        .executableTarget(name: "PotApp", dependencies: ["PotCore", .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "PotDev", dependencies: ["PotCore"]),
        .testTarget(name: "PotCoreTests", dependencies: ["PotCore"])
    ],
    swiftLanguageModes: [.v5]
)
