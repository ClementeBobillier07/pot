// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pot",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PotCore", targets: ["PotCore"]), .executable(name: "Pot", targets: ["PotApp"]), .executable(name: "pot-dev", targets: ["PotDev"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "PotCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "PotApp", dependencies: ["PotCore"]),
        .executableTarget(name: "PotDev", dependencies: ["PotCore"]),
        .testTarget(name: "PotCoreTests", dependencies: ["PotCore"])
    ],
    swiftLanguageModes: [.v5]
)
