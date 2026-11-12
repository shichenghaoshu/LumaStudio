import Foundation
import Combine
import CameraKit
import PhotoDomain
import TetherFolderWatcher

public enum G9Identity {
    public static func isFirstGeneration(_ name: String) -> Bool {
        let n = name.uppercased().replacingOccurrences(of: "LUMIX", with: "").trimmingCharacters(in: .whitespaces)
        return (n.contains("DC-G9") || n == "G9" || n.hasSuffix(" G9")) && !n.contains("G9M2") && !n.contains("G9II") && !n.contains("G9 II")
    }
}
@MainActor public final class LumixTetherFolderAdapter: CameraAdapter, ObservableObject {
    public let capabilities: CameraCapabilities = { var c = CameraCapabilities(); c.supportsRAWTransfer = true; return c }()
    @Published public private(set) var status = "未开始监听"
    public let watcher = FolderWatcher()
    public var folder: URL
    public var onPhoto: FolderWatcher.Handler?
    public init(folder: URL? = nil) {
        #if os(macOS)
        self.folder = folder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/LumaStudio/Inbox")
        #else
        self.folder = folder ?? FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/Inbox")
        #endif
    }
    public func connect() async throws {
        guard let onPhoto else { throw LumaError.unsupported("请先设置自动导入处理器") }
        try await watcher.start(folder: folder, handler: onPhoto) { [weak self] message in await self?.receiveStatus(message) }
        status = "监听中 · 等待 LUMIX Tether 保存照片"
    }
    private func receiveStatus(_ message: String) { status=message }
    public func disconnect() async { await watcher.stop(); status = "已停止监听" }
    public func startLiveView() async throws { throw LumaError.unsupported("请在官方 LUMIX Tether 中使用实时取景。") }
    public func capture() async throws -> CapturedPhoto { throw LumaError.unsupported("请在 LUMIX Tether 中按快门；照片将自动导入。") }
    public func downloadPhotos() async throws { await watcher.scan() }
}
public enum G9WiFiStatus {
    public static let explanation = "G9 直接 Wi-Fi 控制尚未验证。PC(Tether) 模式禁用相机 Wi-Fi / Bluetooth；Mac 与 iPad 局域网传输独立于相机连接。"
}

#if os(macOS)
import ImageCaptureCore

@MainActor public final class NativeCameraAdapter: NSObject, ObservableObject, CameraAdapter, @preconcurrency ICDeviceBrowserDelegate, @preconcurrency ICCameraDeviceDelegate, @preconcurrency ICCameraDeviceDownloadDelegate {
    @Published public private(set) var status = "原生 USB 实验未启动"
    @Published public private(set) var capabilities = CameraCapabilities()
    @Published public private(set) var canTestShutter = false
    @Published public private(set) var fileCount = 0
    public var onCapabilitiesChanged: ((CameraCapabilities) -> Void)?
    public var onDownloaded: (@Sendable (URL) async throws -> Void)?
    public var downloadDirectory: URL
    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var verifiedShutter = false
    private var sessionID=UUID()
    private var captureDownloadInProgress=false
    private var opening: CheckedContinuation<Void, Error>?
    private var capturing: CheckedContinuation<CapturedPhoto, Error>?
    private var downloads: [String: CheckedContinuation<URL, Error>] = [:]
    private var downloaded = Set<String>()
    private var captureBaseline = Set<String>()
    public init(directory: URL) { downloadDirectory = directory; super.init(); browser.delegate = self; browser.browsedDeviceTypeMask = .camera }
    public func connect() async throws {
        browser.start(); status = "正在发现第一代 DC-G9 · 若使用 Tether 请关闭本实验"
    }
    public func disconnect() async {
        try? await camera?.requestCloseSession(); browser.stop(); reset(reason: LumaError.notConnected); camera = nil; status = "原生实验已停止"
    }
    public func startLiveView() async throws { throw LumaError.unsupported("ImageCaptureCore 没有经验证的 G9 实时取景接口。") }
    public func capture() async throws -> CapturedPhoto {
        guard capabilities.supportsRemoteCapture else { throw LumaError.unsupported("请先运行并成功完成原生快门验证。") }
        return try await takePicture()
    }
    public func validateRemoteCapture() async throws -> CapturedPhoto {
        guard canTestShutter else { throw LumaError.unsupported("相机未报告标准拍摄能力，或 tethered capture 未就绪。") }
        let result = try await takePicture(); verifiedShutter = true; refreshCapabilities(); status = "原生快门已在当前连接验证"; return result
    }
    private func takePicture() async throws -> CapturedPhoto {
        guard let camera, camera.hasOpenSession, canTestShutter, capturing == nil else { throw LumaError.notConnected }
        captureBaseline = Set((camera.mediaFiles ?? []).map { $0.name ?? "" })
        return try await withCheckedThrowingContinuation { continuation in
            capturing = continuation; camera.requestTakePicture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                self?.capturing?.resume(throwing: LumaError.unsupported("25 秒内未收到新照片，原生快门未验证。请改用 LUMIX Tether。")); self?.capturing = nil
            }
        }
    }
    public func downloadPhotos() async throws {
        guard let camera, camera.hasOpenSession else { throw LumaError.notConnected }
        for file in (camera.mediaFiles ?? []).compactMap({ $0 as? ICCameraFile }) {
            guard let name = file.name, PhotoFileType.accepts(URL(fileURLWithPath: name)), !downloaded.contains(name) else { continue }
            let url = try await download(file)
            try await onDownloaded?(url); downloaded.insert(name)
        }
    }
    private func download(_ file: ICCameraFile) async throws -> URL {
        guard let camera else { throw LumaError.notConnected }
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let folder=downloadDirectory.appendingPathComponent(sessionID.uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let name = URL(fileURLWithPath:file.name ?? "capture").lastPathComponent
        guard downloads[name] == nil,!FileManager.default.fileExists(atPath:folder.appendingPathComponent(name).path) else { throw LumaError.unsupported("此相机文件已下载或正在下载") }
        return try await withCheckedThrowingContinuation { continuation in
            downloads[name] = continuation
            camera.requestDownloadFile(file, options: [.downloadsDirectoryURL: folder, .saveAsFilename: name, .overwrite: false], downloadDelegate: self, didDownloadSelector: #selector(didDownloadFile(_:error:options:contextInfo:)), contextInfo: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.downloads.removeValue(forKey: name)?.resume(throwing: LumaError.unsupported("相机下载超时")) }
        }
    }
    private func refreshCapabilities() {
        var c = CameraCapabilities()
        if let camera, camera.hasOpenSession {
            canTestShutter = camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanTakePicture.rawValue) && camera.tetheredCaptureEnabled
            c.supportsRemoteCapture = canTestShutter && verifiedShutter
            c.supportsRAWTransfer = true
        } else { canTestShutter = false }
        capabilities = c; onCapabilitiesChanged?(c)
    }
    private func reset(reason: Error) {
        verifiedShutter = false; canTestShutter = false; capabilities = CameraCapabilities(); downloaded.removeAll(); fileCount = 0; onCapabilitiesChanged?(capabilities)
        opening?.resume(throwing: reason); opening = nil; capturing?.resume(throwing: reason); capturing = nil
        for c in downloads.values { c.resume(throwing: reason) }; downloads.removeAll()
    }
    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard camera == nil, let c = device as? ICCameraDevice, G9Identity.isFirstGeneration(c.name ?? "") else { return }
        sessionID=UUID();camera = c; c.delegate = self; status = "发现 \(c.name ?? "DC-G9") · 打开会话"; c.requestOpenSession()
    }
    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) { didRemove(device) }
    public func didRemove(_ device: ICDevice) {
        guard device === camera else { return }; reset(reason: LumaError.notConnected); camera = nil; status = "G9 已断开 · 继续等待重新连接"
    }
    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error { status = error.localizedDescription; reset(reason: error); return }
        // Since macOS 14 requestEnableTethering is documented as a no-op. Only reported state is used.
        refreshCapabilities(); status = "G9 会话已打开 · 标准快门\(canTestShutter ? "可测试" : "不可用")"
    }
    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) { reset(reason: error ?? LumaError.notConnected); status = error?.localizedDescription ?? "会话已关闭" }
    public func deviceDidBecomeReady(_ device: ICDevice) { refreshCapabilities() }
    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) { fileCount = device.mediaFiles?.count ?? 0; refreshCapabilities() }
    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        fileCount = camera.mediaFiles?.count ?? 0
        guard capturing != nil,!captureDownloadInProgress, let file = items.compactMap({ $0 as? ICCameraFile }).first(where: { !captureBaseline.contains($0.name ?? "") && PhotoFileType.accepts(URL(fileURLWithPath: $0.name ?? "")) }) else { return }
        captureDownloadInProgress=true
        Task {
            defer { captureDownloadInProgress=false }
            do { let url = try await download(file); try await onDownloaded?(url); capturing?.resume(returning: CapturedPhoto(url: url)); capturing = nil }
            catch { capturing?.resume(throwing: error); capturing = nil }
        }
    }
    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) { fileCount = camera.mediaFiles?.count ?? 0 }
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) { refreshCapabilities() }
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) { LumaLog.camera.debug("收到相机 PTP 事件") }
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: Error?) {}
    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { refreshCapabilities() }
    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) { canTestShutter = false; capabilities = CameraCapabilities(); status = "相机访问受限" }
    public func device(_ device: ICDevice, didEncounterError error: Error?) { if let error { status = error.localizedDescription } }
    @objc public func didDownloadFile(_ file: ICCameraFile, error: Error?, options: [String : Any], contextInfo: UnsafeMutableRawPointer?) {
        guard let name = options[ICDownloadOption.saveAsFilename.rawValue] as? String, let c = downloads.removeValue(forKey: name) else { return }
        if let error { c.resume(throwing: error) } else { c.resume(returning: downloadDirectory.appendingPathComponent(sessionID.uuidString).appendingPathComponent(name)) }
    }
}
#endif
