// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWhiteboard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacWhiteboard", targets: ["MacWhiteboard"])
    ],
    targets: [
        .target(name: "WhiteboardCore"),
        .executableTarget(name: "MacWhiteboard", dependencies: ["WhiteboardCore"]),
        .testTarget(name: "WhiteboardCoreTests", dependencies: ["WhiteboardCore"]),
    ]
)
