import Foundation
import PhotoDomain

public struct EditingPreferences: Codable,Equatable,Sendable {
    public var confirmationCount=0
    public var beautyStrength: Float=0.35
    public var texturePreservation: Float=0.94
    public var temperature: Float=6500
    public var saturation: Float=1
    public var preferredLUT: String?
    public init() {}
}
/// Only the explicit "remember style" action updates preferences. Nothing becomes training data.
public actor LocalPreferenceMemory {
    private let url: URL
    private var value: EditingPreferences
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        url=directory.appendingPathComponent("preferences.json")
        if FileManager.default.fileExists(atPath:url.path) {
            value=try JSONDecoder().decode(EditingPreferences.self,from:Data(contentsOf:url))
            guard value.confirmationCount>=0,value.confirmationCount<=100000,value.beautyStrength.isFinite,(0...1).contains(value.beautyStrength),value.temperature.isFinite,(2000...12000).contains(value.temperature),value.saturation.isFinite,(0...2).contains(value.saturation) else { throw LumaError.corruptData("本地偏好数据") }
        } else { value=EditingPreferences() }
    }
    public func preferences() -> EditingPreferences { value }
    public func remember(_ recipe: EditRecipe) throws {
        try recipe.validateParameters()
        value.confirmationCount=min(100000,value.confirmationCount+1)
        value.beautyStrength=recipe.beauty.strength;value.texturePreservation=recipe.beauty.texturePreservation
        value.temperature=recipe.global.temperature;value.saturation=recipe.global.saturation;value.preferredLUT=recipe.color.lut
        try JSONEncoder().encode(value).write(to:url,options:.atomic)
    }
    public func clear() throws { value=EditingPreferences();try JSONEncoder().encode(value).write(to:url,options:.atomic) }
}
public actor LocalHistoryStore {
    public let root: URL
    public init(root: URL) throws { self.root=root;try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true) }
    public func directory(assetID: UUID,runID: UUID) throws -> URL {
        let dir=root.appendingPathComponent(assetID.uuidString).appendingPathComponent(runID.uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);return dir
    }
    public func save<T: Encodable>(_ run: T,assetID: UUID,runID: UUID) throws {
        let dir=try directory(assetID:assetID,runID:runID),encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(run).write(to:dir.appendingPathComponent("run.json"),options:.atomic)
    }
    public func clear(assetID: UUID) throws {
        let dir=root.appendingPathComponent(assetID.uuidString)
        if FileManager.default.fileExists(atPath:dir.path) { try FileManager.default.removeItem(at:dir) }
    }
}
