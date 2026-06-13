// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HTMLViewer",
    platforms: [.macOS(.v15)],
    targets: [
        // UI 非依存の判断ロジック層。TDD 対象(swift test で駆動)
        .target(name: "HTMLViewerCore"),
        // SwiftUI シェル(Humble Object 層)。UI 中心のため全型をデフォルト MainActor 隔離にする
        .executableTarget(
            name: "HTMLViewer",
            dependencies: ["HTMLViewerCore"],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "HTMLViewerCoreTests",
            dependencies: ["HTMLViewerCore"]
        ),
    ]
)
