import Foundation
import CryptoKit
import PhotoDomain

public enum ModelRole: String,Codable,CaseIterable,Sendable { case editAgent,vision,beauty,evaluator }
public struct ModelManifest: Codable,Equatable,Sendable,Identifiable {
    public var id: String
    public var version: String
    public var role: ModelRole
    public var displayName: String
    public var filename: String
    public var sha256: String
    public var bytes: UInt64
    public var license: String
    public var licenseURL: String
    public var source: String
    public var platform: [String]
    public var minimumMemoryGB: Int
    public var precision: String
    public var format: String
    public var inputSchema: String
    public var outputSchema: String
    public var trainingStatus: String
    public var benchmarks: [String:String]
    public func validate() throws {
        for value in [id,version] { guard value.range(of:"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$",options:.regularExpression) != nil else { throw LumaError.corruptData("模型 ID 或版本") } }
        guard filename==URL(fileURLWithPath:filename).lastPathComponent,!filename.contains(".."),["gguf","mlmodel","mlpackage"].contains(format),filename.hasSuffix("."+format) else { throw LumaError.corruptData("模型文件名或格式") }
        guard sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,bytes>0,bytes<=16*1024*1024*1024,(1...128).contains(minimumMemoryGB),!license.isEmpty,!source.isEmpty,!inputSchema.isEmpty,!outputSchema.isEmpty,!trainingStatus.isEmpty else { throw LumaError.corruptData("模型清单缺少校验、许可或运行要求") }
        if role == .editAgent,format != "gguf" { throw LumaError.unsupported("当前 Edit Agent 运行器仅支持 GGUF；Core ML 语言模型尚未接入") }
    }
}
public struct InstalledModel: Identifiable,Sendable {
    public let manifest: ModelManifest
    public let url: URL
    public let active: Bool
    public var id: String { manifest.id+"/"+manifest.version }
    public init(manifest: ModelManifest,url: URL,active: Bool) { self.manifest=manifest;self.url=url;self.active=active }
}
public actor ModelManager {
    public let root: URL
    private var selection: [String:String]=[:]
    public init(root: URL) throws {
        self.root=root
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent("active.json")
        if FileManager.default.fileExists(atPath:url.path) { selection=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:url)) }
    }
    public static var defaultRoot: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/ModelPackages") }
    public static func sha256(_ url: URL) throws -> String {
        let resource=try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard resource.isSymbolicLink != true else { throw LumaError.corruptData("模型不能是符号链接") }
        if resource.isDirectory==true {
            let root=url.standardizedFileURL.path+"/"
            guard let items=FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey],options:[]) else { throw LumaError.corruptData("无法枚举模型目录") }
            var entries=[String]()
            for case let item as URL in items {
                let info=try item.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard info.isSymbolicLink != true else { throw LumaError.corruptData("模型包包含符号链接") }
                if info.isRegularFile==true {
                    let path=String(item.standardizedFileURL.path.dropFirst(root.count))
                    guard !path.contains("\n"),!path.contains("\0"),entries.count<4096 else { throw LumaError.corruptData("模型目录无效或过大") }
                    entries.append(path+"\0"+String(info.fileSize ?? 0)+"\0"+(try sha256(item))+"\n")
                }
            }
            guard !entries.isEmpty else { throw LumaError.corruptData("模型目录为空") }
            return SHA256.hash(data:Data(entries.sorted().joined().utf8)).map{String(format:"%02x",$0)}.joined()
        }
        let f=try FileHandle(forReadingFrom:url);defer{try? f.close()};var hash=SHA256()
        while let data=try f.read(upToCount:1024*1024),!data.isEmpty { try Task.checkCancellation();hash.update(data:data) }
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    public static func byteCount(_ url: URL) throws -> UInt64 {
        let values=try url.resourceValues(forKeys:[.isDirectoryKey,.fileSizeKey])
        if values.isDirectory==true {
            guard let items=FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey]) else { throw LumaError.corruptData("模型包目录") }
            var size: UInt64=0
            for case let item as URL in items { let v=try item.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]);if v.isRegularFile==true { size += UInt64(v.fileSize ?? 0) } }
            return size
        };return UInt64(values.fileSize ?? 0)
    }
    public func list() throws -> [InstalledModel] {
        var models=[InstalledModel]()
        for dir in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) where dir.hasDirectoryPath {
            for version in (try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)) ?? [] {
                guard let data=try? Data(contentsOf:version.appendingPathComponent("manifest.json")),let m=try? JSONDecoder().decode(ModelManifest.self,from:data),(try? m.validate()) != nil,
                      dir.lastPathComponent==m.id,version.lastPathComponent==m.version else { continue }
                models.append(InstalledModel(manifest:m,url:version.appendingPathComponent(m.filename),active:selection[m.role.rawValue]==m.id+"/"+m.version))
            }
        }
        return models.sorted{$0.id<$1.id}
    }
    public func install(package: URL,device: DeviceCapabilities) throws -> InstalledModel {
        let manifestURL=package.appendingPathComponent("manifest.json")
        let data=try Data(contentsOf:manifestURL);guard data.count<=64*1024 else { throw LumaError.corruptData("模型清单过大") }
        let m=try JSONDecoder().decode(ModelManifest.self,from:data);try m.validate();try check(m,device:device)
        let source=package.appendingPathComponent(m.filename),values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.isDirectoryKey])
        guard (m.format=="mlpackage" ? values.isDirectory==true : values.isRegularFile==true),values.isSymbolicLink != true,try Self.byteCount(source)==m.bytes else { throw LumaError.corruptData("模型文件大小或文件类型") }
        guard try Self.sha256(source)==m.sha256 else { throw LumaError.corruptData("模型 SHA256 校验失败") }
        let parent=root.appendingPathComponent(m.id),destination=parent.appendingPathComponent(m.version)
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw LumaError.unsupported("此模型版本已安装，可切换或回滚") }
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
        let stage=parent.appendingPathComponent(".install-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:stage)}
        let payload=stage.appendingPathComponent(m.filename);try FileManager.default.copyItem(at:source,to:payload)
        guard try Self.sha256(payload)==m.sha256 else { throw LumaError.corruptData("模型复制后校验失败") }
        try data.write(to:stage.appendingPathComponent("manifest.json"),options:.atomic)
        let license=package.appendingPathComponent("LICENSE.txt")
        if FileManager.default.fileExists(atPath:license.path) { try FileManager.default.copyItem(at:license,to:stage.appendingPathComponent("LICENSE.txt")) }
        try FileManager.default.moveItem(at:stage,to:destination)
        return try activate(id:m.id,version:m.version,device:device)
    }
    private func check(_ m: ModelManifest,device: DeviceCapabilities) throws {
        guard m.platform.contains("macOS"),device.physicalMemoryBytes>=UInt64(m.minimumMemoryGB)*1024*1024*1024 else { throw LumaError.unsupported("此设备不满足模型内存或平台要求") }
    }
    public func activate(id: String,version: String,device: DeviceCapabilities) throws -> InstalledModel {
        guard let item=try list().first(where:{$0.manifest.id==id && $0.manifest.version==version}) else { throw LumaError.unsupported("模型版本不存在") }
        try check(item.manifest,device:device)
        guard try Self.sha256(item.url)==item.manifest.sha256 else { throw LumaError.corruptData("模型已损坏，已拒绝加载") }
        selection[item.manifest.role.rawValue]=item.id;try saveSelection()
        return InstalledModel(manifest:item.manifest,url:item.url,active:true)
    }
    public func activeAgent(device: DeviceCapabilities) throws -> InstalledModel? {
        guard device.supportsNativeAgent else { return nil }
        return try active(role:.editAgent,device:device)
    }
    public func active(role: ModelRole,device: DeviceCapabilities) throws -> InstalledModel? {
        guard let item=try list().first(where:{$0.active && $0.manifest.role == role}) else { return nil }
        try check(item.manifest,device:device)
        guard try Self.sha256(item.url)==item.manifest.sha256 else { throw LumaError.corruptData("模型校验失败，使用本地规则") }
        return item
    }
    public func uninstall(id: String,version: String) throws {
        guard let item=try list().first(where:{$0.manifest.id==id && $0.manifest.version==version}) else { return }
        try FileManager.default.removeItem(at:item.url.deletingLastPathComponent())
        if item.active { selection.removeValue(forKey:item.manifest.role.rawValue);try saveSelection() }
    }
    private func saveSelection() throws { try JSONEncoder().encode(selection).write(to:root.appendingPathComponent("active.json"),options:.atomic) }
}
