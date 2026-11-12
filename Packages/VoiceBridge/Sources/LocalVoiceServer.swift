import Foundation
import Network
import PhotoDomain

public actor LocalVoiceServer {
    private var listener: NWListener?
    private var connections=[UUID:NWConnection]()
    public init() {}
    public func start(token: String,onCommand: @escaping VoiceCommandHandler,onStatus: @escaping VoiceStatusHandler) async throws -> UInt16 {
        guard listener==nil,token.utf8.count>=32 else { throw LumaError.unsupported("本机语音接口已启动或令牌无效") }
        let parameters=NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let server=try NWListener(using:parameters);listener=server
        server.newConnectionHandler={ [weak self] connection in
            Task { await self?.accept(connection,token:token,onCommand:onCommand,onStatus:onStatus) }
        }
        do {
            return try await withCheckedThrowingContinuation { continuation in
                var resolved=false
                server.stateUpdateHandler={ state in
                    switch state {
                    case .ready:if !resolved { resolved=true;continuation.resume(returning:server.port!.rawValue) }
                    case .failed:if !resolved { resolved=true;continuation.resume(throwing:LumaError.unsupported("无法启动本机语音接口")) }
                    case .cancelled:if !resolved { resolved=true;continuation.resume(throwing:CancellationError()) }
                    default:break
                    }
                }
                server.start(queue:DispatchQueue(label:"studio.luma.voice.listener"))
            }
        } catch { server.cancel();listener=nil;throw error }
    }
    public func stop() { listener?.cancel();listener=nil;for c in connections.values { c.cancel() };connections.removeAll() }
    private func accept(_ connection: NWConnection,token: String,onCommand: @escaping VoiceCommandHandler,onStatus: @escaping VoiceStatusHandler) {
        guard connections.count<16 else { connection.cancel();return }
        let id=UUID();connections[id]=connection
        connection.start(queue:DispatchQueue(label:"studio.luma.voice.connection"))
        receive(connection,id:id,buffer:Data(),token:token,onCommand:onCommand,onStatus:onStatus)
        Task { try? await Task.sleep(for:.seconds(10));self.close(id) }
    }
    private func close(_ id: UUID) { connections.removeValue(forKey:id)?.cancel() }
    private func receive(_ connection: NWConnection,id: UUID,buffer: Data,token: String,onCommand: @escaping VoiceCommandHandler,onStatus: @escaping VoiceStatusHandler) {
        connection.receive(minimumIncompleteLength:1,maximumLength:12288) { [weak self] data,_,complete,error in
            Task { await self?.consume(connection,id:id,buffer:buffer+(data ?? Data()),ended:complete || error != nil,token:token,onCommand:onCommand,onStatus:onStatus) }
        }
    }
    private func consume(_ connection: NWConnection,id: UUID,buffer: Data,ended: Bool,token: String,onCommand: @escaping VoiceCommandHandler,onStatus: @escaping VoiceStatusHandler) async {
        guard buffer.count<=12288 else { send(connection,id:id,status:413,body:["error":"Request too large"]);return }
        guard let split=buffer.range(of:Data("\r\n\r\n".utf8)) else {
            if buffer.count>4096 || ended { send(connection,id:id,status:400,body:["error":"Invalid headers"]) }
            else { receive(connection,id:id,buffer:buffer,token:token,onCommand:onCommand,onStatus:onStatus) };return
        }
        guard split.lowerBound<=4096,let header=String(data:buffer[..<split.lowerBound],encoding:.utf8) else { send(connection,id:id,status:400,body:["error":"Invalid headers"]);return }
        let lines=header.components(separatedBy:"\r\n"),parts=lines[0].split(separator:" ")
        guard parts.count==3 else { send(connection,id:id,status:400,body:["error":"Invalid request"]);return }
        var fields=[String:String]()
        for line in lines.dropFirst() {
            let pair=line.split(separator:":",maxSplits:1).map{String($0).trimmingCharacters(in:.whitespaces)}
            guard pair.count==2,fields[pair[0].lowercased()]==nil else { send(connection,id:id,status:400,body:["error":"Invalid headers"]);return }
            fields[pair[0].lowercased()]=pair[1]
        }
        guard fields["transfer-encoding"]==nil,fields["origin"]==nil else { send(connection,id:id,status:400,body:["error":"Unsupported request"]);return }
        guard Self.equalToken(fields["authorization"] ?? "","Bearer "+token) else { send(connection,id:id,status:401,body:["error":"Unauthorized"]);return }
        let length=fields["content-length"].flatMap(Int.init) ?? 0
        guard (0...8192).contains(length) else { send(connection,id:id,status:413,body:["error":"Request too large"]);return }
        let body=buffer[split.upperBound...]
        guard body.count>=length else {
            if ended { send(connection,id:id,status:400,body:["error":"Incomplete request"]) }
            else { receive(connection,id:id,buffer:buffer,token:token,onCommand:onCommand,onStatus:onStatus) };return
        }
        guard body.count==length else { send(connection,id:id,status:400,body:["error":"Unexpected request body"]);return }
        do {
            let response: Data
            if parts[0]=="POST",parts[1]=="/v1/voice/commands" { response=try JSONEncoder().encode(await onCommand(VoiceCommand.decode(Data(body)))) }
            else if parts[0]=="GET",parts[1]=="/v1/status" { response=try JSONEncoder().encode(await onStatus()) }
            else { send(connection,id:id,status:404,body:["error":"Not found"]);return }
            sendData(connection,id:id,status:200,data:response)
        } catch { send(connection,id:id,status:422,body:["error":"Voice command rejected"]) }
    }
    private func send(_ connection: NWConnection,id: UUID,status: Int,body: [String:String]) { sendData(connection,id:id,status:status,data:(try? JSONEncoder().encode(body)) ?? Data()) }
    private func sendData(_ connection: NWConnection,id: UUID,status: Int,data: Data) {
        let header="HTTP/1.1 \(status) Response\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content:Data(header.utf8)+data,completion:.contentProcessed { [weak self] _ in Task { await self?.close(id) } })
    }
    private static func equalToken(_ a: String,_ b: String)->Bool {
        let x=Array(a.utf8),y=Array(b.utf8);guard x.count==y.count else { return false }
        return zip(x,y).reduce(UInt8(0)){$0 | ($1.0 ^ $1.1)}==0
    }
}
