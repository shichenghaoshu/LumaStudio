import Foundation
import CryptoKit
import PhotoDomain

public struct UserFilter: Codable,Equatable,Identifiable,Sendable {
    public let id: String,name: String
}
/// Imported cubes are immutable and addressed by SHA-256; recipes never contain paths.
public enum UserFilterLibrary {
    public static var root: URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LumaStudio/LUTs",isDirectory:true)}
    public static func all(at directory: URL = root)->[UserFilter] {
        let files=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        return files.filter{$0.pathExtension=="json"}.compactMap {url in
            guard let data=try? Data(contentsOf:url),data.count<4096,let f=try? JSONDecoder().decode(UserFilter.self,from:data),f.id.hasPrefix("user_"),FilterIdentifiers.isValid(f.id) else {return nil};return f
        }.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    @discardableResult public static func importCube(_ url: URL,at directory: URL = root)throws->UserFilter {
        let data=try boundedRead(url)
        _=try LUT3D(cube:String(decoding:data,as:UTF8.self))
        let id="user_"+SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        let record=UserFilter(id:id,name:String(url.deletingPathExtension().lastPathComponent.prefix(80)))
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let cube=directory.appendingPathComponent(id+".cube")
        // Re-import also repairs a corrupted cached copy at this content address.
        try data.write(to:cube,options:.atomic)
        try JSONEncoder().encode(record).write(to:directory.appendingPathComponent(id+".json"),options:.atomic)
        return record
    }
    public static func load(id: String,at directory: URL = root)throws->LUT3D {
        guard id.hasPrefix("user_"),FilterIdentifiers.isValid(id) else {throw LumaError.unsupported("未注册的滤镜")}
        let url=directory.appendingPathComponent(id+".cube")
        guard FileManager.default.fileExists(atPath:url.path) else {throw LumaError.unsupported("本机缺少配方使用的自定义 CUBE，请先导入对应滤镜")}
        let data=try boundedRead(url),hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        guard id=="user_"+hash else {throw LumaError.corruptData("自定义滤镜校验失败，请重新导入")}
        return try LUT3D(cube:String(decoding:data,as:UTF8.self))
    }
    private static func boundedRead(_ url: URL)throws->Data {
        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size>0,size<=8*1024*1024 else {throw LumaError.unsupported("CUBE 文件需小于 8 MB，维度为 2…65")}
        let data=try Data(contentsOf:url);guard data.count<=8*1024*1024 else {throw LumaError.corruptData("CUBE 文件超过限制")};return data
    }
}
