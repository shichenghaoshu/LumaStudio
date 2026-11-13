import Foundation
import CoreGraphics
import PhotoDomain
import PhotoPipeline
import ColorEngine
import VisionEngine
import ToolRegistry

public protocol ImageEngine: Sendable {
    func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis
    func render(_ asset: PhotoAsset,recipe: EditRecipe) async throws -> RenderResult
    func preview(_ asset: PhotoAsset,recipe: EditRecipe) async throws -> RenderResult
}
public actor NativeImageEngine: ImageEngine {
    private let processor: PhotoProcessor
    private let registry: ToolRegistry
    private let profile: ColorProfile?
    private let raw: RAWSettings
    public init(processor: PhotoProcessor,profile: ColorProfile?=nil,registry: ToolRegistry=ToolRegistry(),raw: RAWSettings=RAWSettings()) { self.processor=processor;self.profile=profile;self.registry=registry;self.raw=raw }
    public func analyze(_ asset: PhotoAsset) async throws -> ImageAnalysis {
        var neutral=Recipe();neutral.color.enabled=false;neutral.raw=raw
        let result=try await processor.render(url:asset.originalURL,recipe:neutral,tier:.preview)
        return try VisionAnalyzer.analyze(result.original)
    }
    public func render(_ asset: PhotoAsset,recipe: EditRecipe) async throws -> RenderResult { try await perform(asset,recipe:recipe,tier:.fullResolution) }
    public func preview(_ asset: PhotoAsset,recipe: EditRecipe) async throws -> RenderResult { try await perform(asset,recipe:recipe,tier:.preview) }
    private func perform(_ asset: PhotoAsset,recipe: EditRecipe,tier: RenderTier) async throws -> RenderResult {
        try registry.validate(recipe);try Task.checkCancellation()
        return try await processor.render(url:asset.originalURL,recipe:recipe.legacyRecipe(),tier:tier,profile:profile)
    }
}
