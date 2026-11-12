import Foundation
import PhotoDomain
import Darwin

public struct FileFingerprint: Equatable, Sendable {
    public let size: Int64
    public let modified: Date
    public init(size: Int64, modified: Date) { self.size = size; self.modified = modified }
    public static func read(_ url: URL) throws -> FileFingerprint {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(size: (a[.size] as? NSNumber)?.int64Value ?? 0, modified: (a[.modificationDate] as? Date) ?? .distantPast)
    }
}
/// A quiet window is required; one directory event never implies a complete file.
public struct StableFileGate: Sendable {
    private struct Observation: Sendable { var fingerprint: FileFingerprint; var since: Date; var samples: Int }
    private var observations: [URL: Observation] = [:]
    public init() {}
    public mutating func observe(_ url: URL, fingerprint: FileFingerprint, now: Date, quietPeriod: TimeInterval = 2) -> Bool {
        guard fingerprint.size > 0 else { return false }
        if var old = observations[url], old.fingerprint == fingerprint {
            old.samples += 1; observations[url] = old
            return old.samples >= 3 && now.timeIntervalSince(old.since) >= quietPeriod && now.timeIntervalSince(fingerprint.modified) >= quietPeriod
        }
        observations[url] = Observation(fingerprint: fingerprint, since: now, samples: 1)
        return false
    }
    public mutating func retain(_ urls: Set<URL>) { observations = observations.filter { urls.contains($0.key) } }
}

public actor FolderWatcher {
    public typealias Handler = @Sendable (URL) async throws -> Void
    private var pollTask: Task<Void, Never>?
    private var source: DispatchSourceFileSystemObject?
    private var watchedID: String?
    private var folder: URL?
    private var gate = StableFileGate()
    private var completed: [URL: FileFingerprint] = [:]
    private var retryAfter: [URL: Date] = [:]
    private var scanning = false
    private var handler: Handler?
    private var event: (@Sendable (String) async -> Void)?
    public init() {}
    public func start(folder: URL, handler: @escaping Handler, event: (@Sendable (String) async -> Void)? = nil) throws {
        stop()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder; self.handler = handler; self.event = event
        installSource(folder)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scan()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    public func stop() {
        pollTask?.cancel(); pollTask = nil; source?.cancel(); source = nil; watchedID = nil
        folder = nil; handler = nil; gate = StableFileGate(); completed.removeAll(); retryAfter.removeAll()
    }
    private func installSource(_ url: URL) {
        source?.cancel(); source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedID = (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier).map { String(describing: $0) }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: .global(qos: .utility))
        s.setEventHandler { [weak self] in Task { await self?.scan() } }
        s.setCancelHandler { close(fd) }; source = s; s.resume()
    }
    public func scan() async {
        guard !scanning, let folder, let handler else { return }
        scanning = true; defer { scanning = false }
        do {
            let id = (try folder.resourceValues(forKeys: [.fileResourceIdentifierKey])).fileResourceIdentifier.map { String(describing: $0) }
            if id != watchedID || source == nil { installSource(folder); await event?("监听已恢复") }
            let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]).filter { PhotoFileType.accepts($0) && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true) }
            gate.retain(Set(urls))
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !Task.isCancelled, let fingerprint = try? FileFingerprint.read(url), completed[url] != fingerprint else { continue }
                guard gate.observe(url, fingerprint: fingerprint, now: Date()), Date() >= (retryAfter[url] ?? .distantPast) else { continue }
                do {
                    try await handler(url)
                    // Changed while copying? The library also verifies before committing.
                    if (try? FileFingerprint.read(url)) == fingerprint { completed[url] = fingerprint; retryAfter[url] = nil }
                    await event?("照片已自动导入")
                } catch {
                    retryAfter[url] = Date().addingTimeInterval(5)
                    await event?("导入失败，将重试：\(error.localizedDescription)")
                }
            }
        } catch { source?.cancel(); source = nil; watchedID = nil; await event?("目录暂不可用，等待恢复") }
    }
}
