import Foundation
public struct InstructionConstraints: Codable,Equatable,Sendable {
    public var brightnessDirection=0
    public var saturationDirection=0
    public var warmthDirection=0
    public var beautyRequested=false
    public var beautyForbidden=false
    public var preserveTexture=true
    public var requestedLocalRegion: MaskKind?
    public var unavailableRequests: [String]=[]
    public init() {}
}
