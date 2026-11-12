import Foundation
import PhotoDomain

@MainActor public protocol CameraAdapter: AnyObject {
    var capabilities: CameraCapabilities { get }
    func connect() async throws
    func disconnect() async
    func startLiveView() async throws
    func capture() async throws -> CapturedPhoto
    func downloadPhotos() async throws
}
