import Foundation
import CryptoKit
import Security
import PhotoDomain

public struct PairingInvitation: Codable, Sendable {
    public let version: Int
    public let serviceName: String
    public let key: Data
    public let expires: Date
    public init(serviceName: String,key: Data,expires: Date = Date().addingTimeInterval(900)) { version=1;self.serviceName=serviceName;self.key=key;self.expires=expires }
    public func validate(checkExpiry: Bool = true) throws {
        guard version==1,key.count==32,!serviceName.isEmpty,serviceName.count<80,(!checkExpiry || expires>Date()) else { throw LumaError.corruptData("配对邀请无效或已过期") }
    }
    public func text() throws -> String { try "lumastudio://pair/"+JSONEncoder().encode(self).base64EncodedString() }
    public init(text: String) throws {
        guard text.hasPrefix("lumastudio://pair/"),text.utf8.count<4096, let d=Data(base64Encoded:String(text.dropFirst("lumastudio://pair/".count))) else { throw LumaError.corruptData("配对链接格式") }
        self=try JSONDecoder().decode(Self.self,from:d);try validate()
    }
}
public enum PairingKeychain {
    public static func randomKey() throws -> Data {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else { throw LumaError.corruptData("安全随机数不可用") };return Data(bytes)
    }
    public static func save(_ data: Data,account: String) throws {
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"studio.luma.local-pairing",kSecAttrAccount as String:account]
        SecItemDelete(q as CFDictionary)
        var add=q;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result=SecItemAdd(add as CFDictionary,nil)
        guard result==errSecSuccess else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(result)) }
    }
    public static func load(account: String) -> Data? {
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"studio.luma.local-pairing",kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess else { return nil };return result as? Data
    }
}
public struct WirePacket: Codable, Sendable {
    public enum Kind: String,Codable,Sendable { case hello, offer, chunk, finish, ack, failure, capture }
    public var kind: Kind
    public var transferID: UUID?
    public var filename: String?
    public var size: Int64?
    public var sha256: String?
    public var offset: Int64?
    public var bytes: Data?
    public var canCapture: Bool?
    public var message: String?
    public init(_ kind: Kind) { self.kind=kind }
}
public enum SyncFraming {
    public static let maxFrameSize=512*1024
    public static let chunkSize=128*1024
    public static let maxFileSize: Int64=2*1024*1024*1024
    public static func frame(_ packet: WirePacket) throws -> Data {
        let data=try JSONEncoder().encode(packet)
        guard data.count<=maxFrameSize else { throw LumaError.corruptData("传输帧过大") }
        var size=UInt32(data.count).bigEndian;var result=Data(bytes:&size,count:4);result.append(data);return result
    }
    public static func length(_ header: Data) throws -> Int {
        guard header.count==4 else { throw LumaError.corruptData("帧头长度") }
        let count=header.reduce(UInt32(0)){($0<<8)|UInt32($1)}
        guard count>0,count<=maxFrameSize else { throw LumaError.corruptData("传输帧长度超限") };return Int(count)
    }
    public static func validateFilename(_ name: String) throws {
        guard name == URL(fileURLWithPath:name).lastPathComponent,!name.contains("/"),!name.contains("\\"),!name.hasPrefix("."),name.utf8.count<=240,PhotoFileType.accepts(URL(fileURLWithPath:name)) else { throw LumaError.corruptData("不安全的照片文件名") }
    }
}
