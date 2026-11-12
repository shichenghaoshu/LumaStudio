import XCTest
import Foundation
import Network
import CryptoKit
import PhotoDomain
@testable import LocalSync
final class SyncTests: XCTestCase {
    func testFramingAndOversizeRejection() throws {
        var p=WirePacket(.chunk);p.bytes=Data(repeating:1,count:4096)
        let frame=try SyncFraming.frame(p);XCTAssertEqual(try SyncFraming.length(Data(frame.prefix(4))),frame.count-4)
        XCTAssertThrowsError(try SyncFraming.length(Data([255,255,255,255])))
        p.bytes=Data(repeating:0,count:SyncFraming.maxFrameSize);XCTAssertThrowsError(try SyncFraming.frame(p))
        for name in ["../photo.jpg","/tmp/photo.jpg",".secret.jpg","folder\\photo.jpg","script.sh"] {XCTAssertThrowsError(try SyncFraming.validateFilename(name))}
    }
    func testPairingEntropyAndExpiry() throws {
        let key=try PairingKeychain.randomKey();XCTAssertEqual(key.count,32)
        let invitation=PairingInvitation(serviceName:"Luma-test",key:key)
        let decoded=try PairingInvitation(text:invitation.text());XCTAssertEqual(key,decoded.key)
        let expired=PairingInvitation(serviceName:"test",key:key,expires:.distantPast);XCTAssertThrowsError(try expired.validate())
    }
    @MainActor func awaitReady(_ check: @escaping @MainActor ()->Bool,seconds: Double=10) async throws {
        let start=Date();while !check() {if Date().timeIntervalSince(start)>seconds{throw LumaError.unsupported("Network integration timeout")};try await Task.sleep(for:.milliseconds(50))}
    }
    @MainActor func testTLSPSKChunkTransferAndBonjourDiscovery() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let host=LocalSyncService(receivedDirectory:folder.appendingPathComponent("host")),client=LocalSyncService(receivedDirectory:folder.appendingPathComponent("client"))
        defer{host.stop();client.stop()}
        try host.startHosting(ephemeralKey:PairingKeychain.randomKey());try await awaitReady{host.listeningPort != nil}
        let invitation=try XCTUnwrap(host.invitation),port=try XCTUnwrap(host.listeningPort)
        client.discover();print("SYNC host ready: \(host.status), port=\(port)");fflush(stdout)
        // Connect through loopback for deterministic transport; Bonjour above is independently exercised.
        try client.connect(invitation:invitation,endpoint:.hostPort(host:"127.0.0.1",port:port));do { try await awaitReady{client.connected && host.connected} }
        catch { print("SYNC status host=\(host.status), client=\(client.status), discovered=\(client.discovered)");throw error }
        try await awaitReady{client.discovered.contains(invitation.serviceName)}
        let source=folder.appendingPathComponent("transport.jpg")
        let payload=Data((0..<530_000).map{UInt8($0%251)});try payload.write(to:source)
        try await host.sendPhoto(source)
        let received=(FileManager.default.enumerator(at:folder.appendingPathComponent("client"),includingPropertiesForKeys:[.isRegularFileKey])?.allObjects as? [URL] ?? []).first{(try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}
        let data=try Data(contentsOf:XCTUnwrap(received));XCTAssertEqual(SHA256.hash(data:data),SHA256.hash(data:payload));XCTAssertEqual(client.progress,1)
        XCTAssertFalse(client.remoteCaptureAvailable)
    }
    @MainActor func testWrongPairingKeyCannotConnect() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let host=LocalSyncService(receivedDirectory:folder),client=LocalSyncService(receivedDirectory:folder)
        defer{host.stop();client.stop()}
        try host.startHosting(ephemeralKey:PairingKeychain.randomKey());try await awaitReady{host.listeningPort != nil}
        let invite=PairingInvitation(serviceName:host.invitation!.serviceName,key:try PairingKeychain.randomKey())
        try client.connect(invitation:invite,endpoint:.hostPort(host:"127.0.0.1",port:host.listeningPort!))
        try await Task.sleep(for:.seconds(2));XCTAssertFalse(client.connected);XCTAssertFalse(host.connected)
    }
}
