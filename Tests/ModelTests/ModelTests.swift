import XCTest
import PhotoCore

final class ModelTests: XCTestCase {
    private func package(_ root: URL,version: String="1",corrupt: Bool=false) throws -> URL {
        let p=root.appendingPathComponent("package-"+version);try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true)
        // This tiny file tests package integrity only. It is never presented as a real model.
        let asset=p.appendingPathComponent("agent.gguf");try Data("unit-test package bytes \(version)".utf8).write(to:asset)
        let m: [String:Any]=["id":"test-agent","version":version,"role":"editAgent","displayName":"Unit test package only","filename":"agent.gguf","sha256":corrupt ? String(repeating:"0",count:64) : try ModelManager.sha256(asset),"bytes":try ModelManager.byteCount(asset),"license":"test-fixture","licenseURL":"https://example.invalid/license","source":"unit-test synthetic bytes","platform":["macOS"],"minimumMemoryGB":1,"precision":"test","format":"gguf","inputSchema":"test","outputSchema":"EditRecipe v1","trainingStatus":"NOT A MODEL","benchmarks":["status":"unit-test only"]]
        try JSONSerialization.data(withJSONObject:m).write(to:p.appendingPathComponent("manifest.json"));return p
    }
    func testInstallUpgradeRollbackAndUninstall() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let manager=try ModelManager(root:root.appendingPathComponent("registry")),device=DeviceCapabilityManager().snapshot()
        let one=try await manager.install(package:package(root),device:device);XCTAssertTrue(one.active)
        _=try await manager.install(package:package(root,version:"2"),device:device)
        var list=try await manager.list();XCTAssertEqual(list.count,2);XCTAssertTrue(list.first{$0.manifest.version=="2"}!.active)
        _=try await manager.activate(id:"test-agent",version:"1",device:device)
        list=try await manager.list();XCTAssertTrue(list.first{$0.manifest.version=="1"}!.active)
        try await manager.uninstall(id:"test-agent",version:"1")
        list=try await manager.list();XCTAssertEqual(list.count,1);XCTAssertFalse(list[0].active)
    }
    func testCorruptPackageIsNotInstalledAndTamperingIsDetected() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let manager=try ModelManager(root:root.appendingPathComponent("registry")),device=DeviceCapabilityManager().snapshot()
        do { _=try await manager.install(package:package(root,corrupt:true),device:device);XCTFail("bad hash installed") } catch {}
        let empty=try await manager.list();XCTAssertTrue(empty.isEmpty)
        let item=try await manager.install(package:package(root,version:"good"),device:device)
        try Data("tampered".utf8).write(to:item.url)
        do { _=try await manager.activeAgent(device:device);XCTFail("tampered model loaded") } catch {}
    }
    func testCoreMLDirectoryHashIsDeterministicAndRejectsLinks() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        try Data("one".utf8).write(to:root.appendingPathComponent("a"));try Data("two".utf8).write(to:root.appendingPathComponent("b"))
        let first=try ModelManager.sha256(root);XCTAssertEqual(first,try ModelManager.sha256(root));XCTAssertEqual(try ModelManager.byteCount(root),6)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("link"),withDestinationURL:root.appendingPathComponent("a"))
        XCTAssertThrowsError(try ModelManager.sha256(root))
    }
}
