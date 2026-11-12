import Foundation
import Network
import Security
import CryptoKit
import Combine
import PhotoDomain

private final class FramedConnection: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection=connection }
    func send(_ packet: WirePacket) async throws {
        let data=try SyncFraming.frame(packet)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void,Error>) in connection.send(content:data,completion:.contentProcessed { error in if let error { c.resume(throwing:error) } else { c.resume() } }) }
    }
    private func receive(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            connection.receive(minimumIncompleteLength:count,maximumLength:count) { data,_,complete,error in
                if let error { c.resume(throwing:error) }
                else if let data,data.count==count { c.resume(returning:data) }
                else { c.resume(throwing:LumaError.corruptData(complete ? "连接已关闭" : "传输内容不完整")) }
            }
        }
    }
    func next() async throws -> WirePacket {
        let header=try await receive(4);let size=try SyncFraming.length(header)
        return try JSONDecoder().decode(WirePacket.self,from:await receive(size))
    }
}
@MainActor public final class LocalSyncService: ObservableObject {
    @Published public private(set) var status="局域网未启动"
    @Published public private(set) var discovered: [String]=[]
    @Published public private(set) var connected=false
    @Published public private(set) var remoteCaptureAvailable=false
    @Published public private(set) var progress: Double=0
    @Published public private(set) var isSending=false
    public var onReceived: (@Sendable (URL) async throws -> Void)?
    public var onCapture: (@MainActor () async throws -> URL)?
    public private(set) var hostCaptureVerified=false
    public func updateCaptureCapability(_ verified: Bool) {
        hostCaptureVerified=verified
        if let peer,connected { var p=WirePacket(.hello);p.canCapture=verified;Task { try? await peer.send(p) } }
    }
    public private(set) var invitation: PairingInvitation?
    public private(set) var listeningPort: NWEndpoint.Port?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var results: [String:NWEndpoint]=[:]
    private var peer: FramedConnection?
    private var readTask: Task<Void,Never>?
    private var pending: (UUID,CheckedContinuation<WirePacket,Error>)?
    private let queue=DispatchQueue(label:"studio.luma.localsync",qos:.utility)
    private let receivedDirectory: URL
    private struct Incoming { let id: UUID;let name: String;let size: Int64;let digest: String;let temporary: URL;let handle: FileHandle;var offset: Int64=0;var hash=SHA256() }
    private var incoming: Incoming?
    private var sessionID=UUID()
    public init(receivedDirectory: URL) { self.receivedDirectory=receivedDirectory }
    private func parameters(key: Data,identity: String) throws -> NWParameters {
        guard key.count==32 else { throw LumaError.corruptData("TLS 配对密钥长度") }
        let tls=NWProtocolTLS.Options()
        let secret=key.withUnsafeBytes{DispatchData(bytes:$0)}
        let label=Data(identity.utf8).withUnsafeBytes{DispatchData(bytes:$0)}
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,secret as __DispatchData,label as __DispatchData)
        // Apple Network.framework's external PSK path is negotiated with this AEAD
        // suite on the supported SDKs. No plaintext fallback is permitted.
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,tls_ciphersuite_t(rawValue:UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let p=NWParameters(tls:tls,tcp:NWProtocolTCP.Options());p.includePeerToPeer=false;p.prohibitedInterfaceTypes=[.cellular]
        return p
    }
    public func startHosting(ephemeralKey: Data? = nil) throws {
        stop()
        let key: Data
        if let ephemeralKey { key=ephemeralKey }
        else if let saved=PairingKeychain.load(account:"host-key"),saved.count==32 { key=saved }
        else { key=try PairingKeychain.randomKey();try PairingKeychain.save(key,account:"host-key") }
        let name="Luma-"+String(SHA256.hash(data:key).map{String(format:"%02x",$0)}.joined().prefix(12))
        invitation=PairingInvitation(serviceName:name,key:key)
        let l=try NWListener(using:parameters(key:key,identity:name),on:.any)
        l.service=NWListener.Service(name:name,type:"_lumastudio._tcp")
        l.stateUpdateHandler={ [weak self,weak l] state in Task { @MainActor in
            switch state { case .ready:self?.listeningPort=l?.port;self?.status="本地 Host 已就绪 · 等待配对设备"
            case .failed(let error):self?.status=error.localizedDescription
            default:break }
        } }
        l.newConnectionHandler={ [weak self] connection in Task { @MainActor in self?.attach(connection) } }
        listener=l;l.start(queue:queue);status="正在启动加密局域网 Host"
    }
    public func revokePairings() throws { stop();try PairingKeychain.save(PairingKeychain.randomKey(),account:"host-key");try startHosting() }
    public func discover() {
        browser?.cancel();results.removeAll();discovered=[]
        let b=NWBrowser(for:.bonjour(type:"_lumastudio._tcp",domain:"local."),using:.tcp)
        b.browseResultsChangedHandler={ [weak self] results,_ in Task { @MainActor in
            var endpoints=[String:NWEndpoint]()
            for result in results { if case .service(let name,_,_,_)=result.endpoint { endpoints[name]=result.endpoint } }
            self?.results=endpoints;self?.discovered=endpoints.keys.sorted()
        } }
        b.stateUpdateHandler={ [weak self] state in if case .failed(let e)=state { Task { @MainActor in self?.status=e.localizedDescription } } }
        browser=b;b.start(queue:queue);status="正在发现同一局域网的 Mac"
    }
    public func pair(text: String) throws {
        let invitation=try PairingInvitation(text:text)
        guard let endpoint=results[invitation.serviceName] else { throw LumaError.unsupported("尚未发现邀请中的 Host，请确认同一局域网并稍后重试。") }
        try PairingKeychain.save(JSONEncoder().encode(invitation),account:"trusted-host")
        try connect(invitation:invitation,endpoint:endpoint)
    }
    public func reconnectTrusted() throws {
        guard let data=PairingKeychain.load(account:"trusted-host") else { throw LumaError.notConnected }
        let i=try JSONDecoder().decode(PairingInvitation.self,from:data)
        guard let endpoint=results[i.serviceName] else { throw LumaError.unsupported("已配对 Host 尚未出现在局域网") }
        try connect(invitation:i,endpoint:endpoint)
    }
    public func connect(invitation: PairingInvitation,endpoint: NWEndpoint) throws {
        try invitation.validate(checkExpiry:false)
        attach(NWConnection(to:endpoint,using:try parameters(key:invitation.key,identity:invitation.serviceName)))
    }
    private func attach(_ connection: NWConnection) {
        guard peer==nil else { connection.cancel();return }
        sessionID=UUID();let framed=FramedConnection(connection);peer=framed
        connection.stateUpdateHandler={ [weak self,weak framed] state in Task { @MainActor in
            guard let self,let framed,self.peer === framed else { return }
            switch state {
            case .ready:
                self.connected=true;self.status="已通过配对密钥建立 TLS 1.2 / AES-GCM 连接"
                self.readTask=Task { await self.readLoop(framed) }
                var hello=WirePacket(.hello);hello.canCapture=self.hostCaptureVerified
                try? await framed.send(hello)
            case .failed(let error):self.closePeer(message:error.localizedDescription)
            case .cancelled:self.closePeer(message:"局域网连接已断开")
            default:break
            }
        } }
        connection.start(queue:queue)
        Task { [weak self,weak framed] in
            try? await Task.sleep(for:.seconds(12))
            if let self,let framed,self.peer === framed,!self.connected { self.closePeer(message:"TLS 配对超时，请检查邀请和本地网络权限") }
        }
    }
    private func readLoop(_ channel: FramedConnection) async {
        do { while !Task.isCancelled { let p=try await channel.next();try await handle(p,channel:channel) } }
        catch { if peer === channel { closePeer(message:error.localizedDescription) } }
    }
    private func handle(_ packet: WirePacket,channel: FramedConnection) async throws {
        switch packet.kind {
        case .hello:remoteCaptureAvailable=packet.canCapture == true
        case .ack,.failure:
            if let waiting=pending { pending=nil
                if packet.kind == .failure { waiting.1.resume(throwing:LumaError.unsupported(packet.message ?? "对方拒绝操作")) }
                else { waiting.1.resume(returning:packet) }
            }
        case .offer:
            guard incoming==nil,let id=packet.transferID,let name=packet.filename,let size=packet.size,size>0,size<=SyncFraming.maxFileSize,let digest=packet.sha256,digest.count==64,digest.allSatisfy({$0.isHexDigit}) else { throw LumaError.corruptData("照片传输声明") }
            try SyncFraming.validateFilename(name)
            try FileManager.default.createDirectory(at:receivedDirectory,withIntermediateDirectories:true)
            let tmp=receivedDirectory.appendingPathComponent(".\(UUID().uuidString).partial")
            guard FileManager.default.createFile(atPath:tmp.path,contents:nil) else { throw LumaError.corruptData("无法创建接收文件") }
            incoming=Incoming(id:id,name:name,size:size,digest:digest,temporary:tmp,handle:try FileHandle(forWritingTo:tmp))
            progress=0;try await acknowledge(id:id,offset:0,channel:channel)
        case .chunk:
            guard var file=incoming,file.id==packet.transferID,packet.offset==file.offset,let bytes=packet.bytes,!bytes.isEmpty,bytes.count<=SyncFraming.chunkSize,file.offset+Int64(bytes.count)<=file.size else { throw LumaError.corruptData("照片分块顺序或长度") }
            try file.handle.write(contentsOf:bytes);file.hash.update(data:bytes);file.offset += Int64(bytes.count);incoming=file;progress=Double(file.offset)/Double(file.size)
            try await acknowledge(id:file.id,offset:file.offset,channel:channel)
        case .finish:
            guard let file=incoming,file.id==packet.transferID,file.offset==file.size else { throw LumaError.corruptData("照片未传完") }
            let hash=file.hash.finalize().map{String(format:"%02x",$0)}.joined()
            guard hash==file.digest else { throw LumaError.corruptData("照片 SHA256 校验失败") }
            try file.handle.close()
            var folder=receivedDirectory.appendingPathComponent(sessionID.uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:folder.appendingPathComponent(file.name).path) {
                folder=folder.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            }
            let output=folder.appendingPathComponent(file.name)
            try FileManager.default.moveItem(at:file.temporary,to:output);incoming=nil
            do { try await onReceived?(output);try await acknowledge(id:file.id,offset:file.size,channel:channel);status="照片已校验并导入" }
            catch { var failure=WirePacket(.failure);failure.message=error.localizedDescription;try await channel.send(failure) }
        case .capture:
            guard hostCaptureVerified,let onCapture else { var failure=WirePacket(.failure);failure.message="Host 原生快门尚未通过实机验证";try await channel.send(failure);return }
            Task { [weak self] in
                do { let url=try await onCapture();try await channel.send(WirePacket(.ack));try await self?.sendPhoto(url) }
                catch { var failure=WirePacket(.failure);failure.message=error.localizedDescription;try? await channel.send(failure) }
            }
        }
    }
    private func acknowledge(id: UUID,offset: Int64,channel: FramedConnection) async throws { var p=WirePacket(.ack);p.transferID=id;p.offset=offset;try await channel.send(p) }
    private func exchange(_ packet: WirePacket) async throws -> WirePacket {
        guard connected,let peer,pending==nil else { throw LumaError.notConnected }
        let token=UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending=(token,continuation)
            Task { [weak self] in
                do { try await peer.send(packet) } catch { if self?.pending?.0==token { self?.pending=nil;continuation.resume(throwing:error) } }
            }
            Task { [weak self] in
                try? await Task.sleep(for:.seconds(60))
                if self?.pending?.0==token { self?.pending=nil;continuation.resume(throwing:LumaError.unsupported("局域网操作超时"));self?.closePeer(message:"传输超时") }
            }
        }
    }
    public func sendPhoto(_ url: URL,name: String? = nil) async throws {
        guard !isSending else { throw LumaError.unsupported("正在发送另一张照片") }
        let filename=name ?? url.lastPathComponent
        try SyncFraming.validateFilename(filename)
        isSending=true;progress=0;defer{isSending=false}
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
        var hasher=SHA256();var size: Int64=0
        while let bytes=try file.read(upToCount:SyncFraming.chunkSize),!bytes.isEmpty { hasher.update(data:bytes);size += Int64(bytes.count) }
        guard size>0,size<=SyncFraming.maxFileSize else { throw LumaError.unsupported("照片超过传输大小限制") }
        try file.seek(toOffset:0)
        let id=UUID();var offer=WirePacket(.offer);offer.transferID=id;offer.filename=filename;offer.size=size;offer.sha256=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        let first=try await exchange(offer);guard first.transferID==id,first.offset==0 else { throw LumaError.corruptData("传输确认不匹配") }
        var offset: Int64=0
        while let bytes=try file.read(upToCount:SyncFraming.chunkSize),!bytes.isEmpty {
            try Task.checkCancellation();var p=WirePacket(.chunk);p.transferID=id;p.offset=offset;p.bytes=bytes
            let ack=try await exchange(p);offset += Int64(bytes.count)
            guard ack.transferID==id,ack.offset==offset else { throw LumaError.corruptData("分块确认不匹配") };progress=Double(offset)/Double(size)
        }
        var finish=WirePacket(.finish);finish.transferID=id;let ack=try await exchange(finish)
        guard ack.transferID==id,ack.offset==size else { throw LumaError.corruptData("最终确认不匹配") };status="照片已安全发送"
    }
    public func requestCapture() async throws { guard remoteCaptureAvailable else { throw LumaError.unsupported("Mac 尚未验证原生快门") };_ = try await exchange(WirePacket(.capture)) }
    private func closePeer(message: String) {
        let old=peer;peer=nil;old?.connection.cancel();readTask?.cancel();readTask=nil;connected=false;remoteCaptureAvailable=false
        pending?.1.resume(throwing:LumaError.notConnected);pending=nil
        if let incoming { try? incoming.handle.close();try? FileManager.default.removeItem(at:incoming.temporary) };incoming=nil;status=message
    }
    public func stop() { listener?.cancel();listener=nil;browser?.cancel();browser=nil;invitation=nil;listeningPort=nil;closePeer(message:"局域网已停止") }
}
