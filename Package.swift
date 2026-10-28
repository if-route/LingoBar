// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LingoBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, UI-free logic (parsing, grouping, geometry, prompts, LLM client, OCR).
        .target(name: "LingoBarCore"),
        .executableTarget(name: "LingoBar", dependencies: ["LingoBarCore"])
    ]
)
