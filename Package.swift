// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LumaStudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PhotoCore", targets: ["PhotoCore"]),
        .executable(name: "LumaDiagnostics", targets: ["LumaDiagnostics"]),
        .executable(name: "LumaAgentCLI", targets: ["LumaAgentCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/MetalPetal/MetalPetal.git", exact: "1.25.2"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.1.4")
    ],
    targets: [
        .binaryTarget(name: "llama", path: "Vendor/llama-runtime.xcframework"),
        .target(name: "PhotoDomain", path: "Packages/PhotoDomain/Sources", resources: [.process("Resources")]),
        .target(name: "AgentCore", dependencies: ["PhotoDomain", "PhotoPipeline", "ImageEngine", "ToolRegistry", "VisionEngine", "Evaluator", "ModelManager", "LocalMemory", .target(name: "llama", condition: .when(platforms: [.macOS]))], path: "Packages/AgentCore/Sources"),
        .target(name: "Evaluator", dependencies: ["PhotoDomain", "VisionEngine"], path: "Packages/Evaluator/Sources"),
        .target(name: "ModelManager", dependencies: ["PhotoDomain"], path: "Packages/ModelManager/Sources"),
        .target(name: "LocalMemory", dependencies: ["PhotoDomain"], path: "Packages/LocalMemory/Sources"),
        .target(name: "ToolRegistry", dependencies: ["PhotoDomain"], path: "Packages/ToolRegistry/Sources"),
        .target(name: "VisionEngine", dependencies: ["PhotoDomain"], path: "Packages/VisionEngine/Sources"),
        .target(name: "ImageEngine", dependencies: ["PhotoDomain", "PhotoPipeline", "VisionEngine", "ColorEngine", "ToolRegistry"], path: "Packages/ImageEngine/Sources"),
        .target(name: "CameraKit", dependencies: ["PhotoDomain"], path: "Packages/CameraKit/Sources"),
        .target(name: "TetherFolderWatcher", dependencies: ["PhotoDomain"], path: "Packages/TetherFolderWatcher/Sources"),
        .target(name: "PanasonicG9", dependencies: ["PhotoDomain", "CameraKit", "TetherFolderWatcher"], path: "Packages/PanasonicG9/Sources"),
        .target(name: "BeautyEngine", dependencies: ["PhotoDomain", .product(name: "MetalPetal", package: "MetalPetal", condition: .when(platforms: [.macOS]))], path: "Packages/BeautyEngine/Sources"),
        .target(name: "CloudModel", dependencies: ["PhotoDomain", "AgentCore", "ToolRegistry"], path: "Packages/CloudModel/Sources"),
        .target(name: "VoiceBridge", dependencies: ["PhotoDomain", .product(name: "DequeModule", package: "swift-collections")], path: "Packages/VoiceBridge/Sources"),
        .target(name: "ColorEngine", dependencies: ["PhotoDomain"], path: "Packages/ColorEngine/Sources", resources: [.process("LUTs")]),
        .target(name: "PhotoPipeline", dependencies: ["PhotoDomain", "BeautyEngine", "ColorEngine", "ToolRegistry", "VisionEngine"], path: "Packages/PhotoPipeline/Sources"),
        .target(name: "BatchEngine", dependencies: ["PhotoDomain", "PhotoPipeline", "ColorEngine"], path: "Packages/BatchEngine/Sources"),
        .target(name: "LocalLibrary", dependencies: ["PhotoDomain", "PhotoPipeline"], path: "Packages/LocalLibrary/Sources"),
        .target(name: "LocalSync", dependencies: ["PhotoDomain"], path: "Packages/LocalSync/Sources"),
        .target(name: "PhotoCore", dependencies: ["PhotoDomain", "CameraKit", "PanasonicG9", "TetherFolderWatcher", "BeautyEngine", "ColorEngine", "PhotoPipeline", "BatchEngine", "LocalLibrary", "LocalSync", "ToolRegistry", "VisionEngine", "ImageEngine", "Evaluator", "ModelManager", "LocalMemory", "AgentCore", "CloudModel", "VoiceBridge"], path: "Packages/PhotoCore/Sources"),
        .executableTarget(name: "LumaAgentCLI", dependencies: ["PhotoCore"], path: "Tools/LumaAgentCLI"),
        .executableTarget(name: "LumaDiagnostics", dependencies: ["PhotoCore"], path: "Tools/LumaDiagnostics"),
        .testTarget(name: "AgentTests", dependencies: ["PhotoCore", "PhotoDomain", "AgentCore", "ToolRegistry", "ModelManager", "LocalMemory", "Evaluator", "ImageEngine", "VisionEngine", "PhotoPipeline"], path: "Tests/AgentTests"),
        .testTarget(name: "CloudModelTests", dependencies: ["CloudModel", "PhotoDomain", "AgentCore", "VisionEngine", "ToolRegistry", "LocalMemory"], path: "Tests/CloudModelTests"),
        .testTarget(name: "ProEditorTests", dependencies: ["PhotoCore", "PhotoDomain", "PhotoPipeline", "BeautyEngine", "BatchEngine"], path: "Tests/ProEditorTests"),
        .testTarget(name: "VoiceBridgeTests", dependencies: ["VoiceBridge"], path: "Tests/VoiceBridgeTests"),
        .testTarget(name: "ModelTests", dependencies: ["PhotoCore", "PhotoDomain", "AgentCore", "ToolRegistry", "ModelManager", "LocalMemory", "Evaluator", "ImageEngine", "VisionEngine", "PhotoPipeline"], path: "Tests/ModelTests"),
        .testTarget(name: "MemoryTests", dependencies: ["PhotoCore", "PhotoDomain", "AgentCore", "ToolRegistry", "ModelManager", "LocalMemory", "Evaluator", "ImageEngine", "VisionEngine", "PhotoPipeline"], path: "Tests/MemoryTests"),
        .testTarget(name: "ImageTests", dependencies: ["PhotoCore", "PhotoDomain", "AgentCore", "ToolRegistry", "ModelManager", "LocalMemory", "Evaluator", "ImageEngine", "VisionEngine", "PhotoPipeline"], path: "Tests/ImageTests"),
        .testTarget(name: "DeviceTests", dependencies: ["PhotoCore", "PhotoDomain", "AgentCore", "ToolRegistry", "ModelManager", "LocalMemory", "Evaluator", "ImageEngine", "VisionEngine", "PhotoPipeline"], path: "Tests/DeviceTests"),
        .testTarget(name: "CameraTests", dependencies: ["PanasonicG9", "TetherFolderWatcher"], path: "Tests/CameraTests"),
        .testTarget(name: "BeautyTests", dependencies: ["BeautyEngine"], path: "Tests/BeautyTests"),
        .testTarget(name: "ColorTests", dependencies: ["ColorEngine"], path: "Tests/ColorTests"),
        .testTarget(name: "BatchTests", dependencies: ["BatchEngine"], path: "Tests/BatchTests"),
        .testTarget(name: "RAWTests", dependencies: ["PhotoPipeline"], path: "Tests/RAWTests"),
        .testTarget(name: "LibraryTests", dependencies: ["LocalLibrary"], path: "Tests/LibraryTests"),
        .testTarget(name: "SyncTests", dependencies: ["LocalSync"], path: "Tests/SyncTests")
    ]
)
