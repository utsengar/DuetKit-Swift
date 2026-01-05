// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuetKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Duet", targets: ["Duet"]),
        .library(name: "DuetChat", targets: ["DuetChat"]),
        .executable(name: "DuetCLI", targets: ["DuetCLI"]),
    ],
    targets: [
        .target(
            name: "Duet",
            dependencies: []
        ),
        .target(
            name: "DuetChat",
            dependencies: []
        ),
        .executableTarget(
            name: "DuetCLI",
            dependencies: ["Duet"]
        ),
    ]
)
