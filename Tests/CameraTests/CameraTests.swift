import XCTest
@testable import PanasonicG9
import TetherFolderWatcher
final class CameraTests: XCTestCase {
    func testFirstGenerationOnly() {
        XCTAssertTrue(G9Identity.isFirstGeneration("Panasonic DC-G9"))
        XCTAssertTrue(G9Identity.isFirstGeneration("LUMIX G9"))
        for name in ["DC-G9M2", "LUMIX G9 II", "DC-GH5", "G9II"] { XCTAssertFalse(G9Identity.isFirstGeneration(name)) }
    }
    func testStableFileGateRequiresQuietWindow() {
        var gate = StableFileGate(); let u = URL(fileURLWithPath: "/tmp/test.RW2"); let now = Date()
        let a = FileFingerprint(size: 10, modified: now)
        XCTAssertFalse(gate.observe(u, fingerprint: a, now: now))
        XCTAssertFalse(gate.observe(u, fingerprint: a, now: now.addingTimeInterval(1)))
        XCTAssertTrue(gate.observe(u, fingerprint: a, now: now.addingTimeInterval(2.1)))
        XCTAssertFalse(gate.observe(u, fingerprint: .init(size: 20, modified: now.addingTimeInterval(3)), now: now.addingTimeInterval(3)))
    }
}
actor SeenFiles {
    var names=[String]()
    func append(_ url: URL) { names.append(url.lastPathComponent) }
    func count()->Int { names.count }
}
extension CameraTests {
    func testWatcherDelayedWriteAndDirectoryRecovery() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);let seen=SeenFiles();let watcher=FolderWatcher()
        try await watcher.start(folder:dir){url in await seen.append(url)}
        let photo=dir.appendingPathComponent("capture.jpg");try Data([1]).write(to:photo)
        try await Task.sleep(for:.seconds(1));let before=await seen.count();XCTAssertEqual(before,0)
        try Data([1,2,3]).write(to:photo)
        try await Task.sleep(for:.seconds(3.5));let after=await seen.count();XCTAssertEqual(after,1)
        try await Task.sleep(for:.seconds(1));let dedup=await seen.count();XCTAssertEqual(dedup,1)
        try FileManager.default.removeItem(at:dir);try await Task.sleep(for:.seconds(1.2));try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try Data([4,5]).write(to:dir.appendingPathComponent("reconnected.jpg"))
        try await Task.sleep(for:.seconds(3.5));let recovered=await seen.count();XCTAssertEqual(recovered,2)
        await watcher.stop();try? FileManager.default.removeItem(at:dir)
    }
}
