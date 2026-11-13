import Foundation
import SwiftData
import ImageIO
import CryptoKit
import PhotoDomain
import PhotoPipeline
import CoreImage

@Model final class StoredPhoto {
    @Attribute(.unique) var id: UUID
    var name: String
    var primaryPath: String
    var companionPath: String?
    var thumbnailPath: String
    var pairKey: String
    var sourceModified: Date
    var importedAt: Date
    var recipeData: Data?
    // Optional so existing libraries migrate without changing photo or recipe data.
    var reviewData: Data?
    init(id: UUID, name: String, primary: String, thumbnail: String, pairKey: String, modified: Date) {
        self.id = id; self.name = name; self.primaryPath = primary; self.thumbnailPath = thumbnail
        self.pairKey = pairKey; self.sourceModified = modified; self.importedAt = Date()
    }
}
@Model final class ImportedFile {
    @Attribute(.unique) var digest: String
    var photoID: UUID
    init(digest: String, photoID: UUID) { self.digest = digest; self.photoID = photoID }
}
public struct ImportResult: Sendable { public let asset: PhotoAsset; public let duplicate: Bool }

public enum ContentDigest {
    public static func sha256(_ url: URL) throws -> String {
        let f = try FileHandle(forReadingFrom: url); defer { try? f.close() }
        var hasher = SHA256()
        while let data = try f.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public actor PhotoLibrary: ModelActor {
    public nonisolated let root: URL
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private var context: ModelContext { modelContext }
    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        for sub in ["Originals", "Thumbnails", "Recipes", "Profiles", "Exports", ".staging"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let schema = Schema([StoredPhoto.self, ImportedFile.self])
        let config = ModelConfiguration("LumaLibrary", schema: schema, url: root.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        let localContext = ModelContext(modelContainer); localContext.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: localContext)
        // Only staging files are disposable. Originals are never removed during recovery.
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(".staging"), includingPropertiesForKeys: nil) {
            for item in leftovers { try? FileManager.default.removeItem(at: item) }
        }
    }
    public func list() throws -> [PhotoAsset] {
        try context.fetch(FetchDescriptor<StoredPhoto>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)])).map(asset)
    }
    private func asset(_ p: StoredPhoto) -> PhotoAsset {
        PhotoAsset(id: p.id, name: p.name, originalURL: root.appendingPathComponent(p.primaryPath), companionURL: p.companionPath.map { root.appendingPathComponent($0) }, thumbnailURL: root.appendingPathComponent(p.thumbnailPath), importedAt: p.importedAt)
    }
    public func importPhoto(_ source: URL) throws -> ImportResult {
        guard PhotoFileType.accepts(source), (try source.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw LumaError.invalidImage(source.lastPathComponent) }
        let fm = FileManager.default
        let before = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let staging = root.appendingPathComponent(".staging/\(UUID().uuidString).\(source.pathExtension)")
        try fm.copyItem(at: source, to: staging); defer { try? fm.removeItem(at: staging) }
        let after = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else { throw LumaError.corruptData("文件仍在写入，请稍后重试") }
        let digest = try ContentDigest.sha256(staging)
        let digestQuery = FetchDescriptor<ImportedFile>(predicate: #Predicate { $0.digest == digest })
        if let existing = try context.fetch(digestQuery).first {
            let photoID = existing.photoID
            if let photo = try context.fetch(FetchDescriptor<StoredPhoto>(predicate: #Predicate { $0.id == photoID })).first { return ImportResult(asset: asset(photo), duplicate: true) }
        }
        let thumb: CGImage
        if let imageSource=CGImageSourceCreateWithURL(staging as CFURL,nil),CGImageSourceGetStatus(imageSource) == .statusComplete,let image=CGImageSourceCreateThumbnailAtIndex(imageSource,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:360] as CFDictionary) {thumb=image}
        else if PhotoFileType.isRAW(staging) {
            let decoded=try ImageDecoder().decode(staging,tier:.thumbnail)
            guard let image=CIContext().createCGImage(decoded,from:decoded.extent) else {throw LumaError.invalidImage(source.lastPathComponent)}
            thumb=image
        } else {throw LumaError.invalidImage(source.lastPathComponent)}
        let ext = source.pathExtension.lowercased()
        let primary = "Originals/\(digest).\(ext)"
        let destination = root.appendingPathComponent(primary)
        let pairKey = source.deletingPathExtension().standardizedFileURL.path.lowercased()
        let modified = before.contentModificationDate ?? Date()
        let candidates = try context.fetch(FetchDescriptor<StoredPhoto>(predicate: #Predicate { $0.pairKey == pairKey }))
        let sourceRAW = PhotoFileType.isRAW(source)
        let partner = candidates.first { $0.companionPath == nil && PhotoFileType.isRAW(URL(fileURLWithPath: $0.primaryPath)) != sourceRAW && abs($0.sourceModified.timeIntervalSince(modified)) < 15 }
        let id = partner?.id ?? UUID()
        let thumbPath = "Thumbnails/\(id.uuidString).jpg"
        guard let output = CGImageDestinationCreateWithURL(root.appendingPathComponent(thumbPath) as CFURL, "public.jpeg" as CFString, 1, nil) else { throw LumaError.invalidImage("缩略图目标") }
        CGImageDestinationAddImage(output, thumb, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw LumaError.invalidImage("缩略图写入失败") }
        if !fm.fileExists(atPath: destination.path) { try fm.moveItem(at: staging, to: destination) }
        let stored: StoredPhoto
        if let partner {
            if sourceRAW { partner.companionPath = partner.primaryPath; partner.primaryPath = primary; partner.name = source.lastPathComponent }
            else { partner.companionPath = primary }
            stored = partner
        } else {
            stored = StoredPhoto(id: id, name: source.lastPathComponent, primary: primary, thumbnail: thumbPath, pairKey: pairKey, modified: modified)
            context.insert(stored)
        }
        context.insert(ImportedFile(digest: digest, photoID: id))
        do { try context.save() } catch { context.rollback(); throw error }
        return ImportResult(asset: asset(stored), duplicate: false)
    }
    public func saveRecipe(_ recipe: Recipe, for id: UUID) throws {
        guard let photo = try context.fetch(FetchDescriptor<StoredPhoto>(predicate: #Predicate { $0.id == id })).first else { throw LumaError.corruptData("照片已不在当前图库") }
        let data = try recipe.json()
        photo.recipeData = data
        do { try context.save() } catch { context.rollback(); throw error }
    }
    public func recipe(for id: UUID) throws -> Recipe {
        guard let photo = try context.fetch(FetchDescriptor<StoredPhoto>(predicate: #Predicate { $0.id == id })).first, let data = photo.recipeData else { return Recipe() }
        return try JSONDecoder().decode(Recipe.self, from: data).validated()
    }
    public func reviews() throws -> [UUID: PhotoReview] {
        var result = [UUID: PhotoReview]()
        for photo in try context.fetch(FetchDescriptor<StoredPhoto>()) {
            if let data = photo.reviewData { result[photo.id] = try JSONDecoder().decode(PhotoReview.self, from: data).validated() }
        }
        return result
    }
    public func updateReviews(for ids: Set<UUID>, rating: Int? = nil, flag: PhotoFlag? = nil) throws {
        if let rating, !(0...5).contains(rating) { throw LumaError.corruptData("星标需在 0–5 之间") }
        let photos = try photos(matching: ids)
        // Prepare everything before mutating the context, including corrupt-data checks.
        let updates = try photos.map { photo -> (StoredPhoto, Data) in
            var review = try photo.reviewData.map { try JSONDecoder().decode(PhotoReview.self, from: $0).validated() } ?? PhotoReview()
            if let rating { review.rating = rating }; if let flag { review.flag = flag }
            return (photo, try JSONEncoder().encode(review))
        }
        for (photo, data) in updates { photo.reviewData = data }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    public func synchronizeRecipe(_ source: Recipe, from sourceID: UUID, to ids: Set<UUID>, groups: Set<RecipeSyncGroup>) throws -> RecipeSyncTransaction {
        guard !groups.isEmpty else { throw LumaError.unsupported("请至少选择一个参数分组") }
        _ = try photos(matching: [sourceID])
        let targets = try photos(matching: ids.subtracting([sourceID]))
        guard !targets.isEmpty else { throw LumaError.unsupported("请选择当前照片以外的目标照片") }
        var changes = [RecipeSyncChange](), updates = [(StoredPhoto, Data)]()
        for photo in targets {
            let before = try decodedRecipe(photo)
            let after = try RecipeSynchronization.applying(source, to: before, groups: groups, targetIsRAW: PhotoFileType.isRAW(URL(fileURLWithPath: photo.primaryPath)))
            if after != before {
                changes.append(RecipeSyncChange(id: photo.id, before: before, after: after))
                updates.append((photo, try after.json()))
            }
        }
        for (photo, data) in updates { photo.recipeData = data }
        do { try context.save() } catch { context.rollback(); throw error }
        let skipped = groups.contains(.raw) ? targets.filter { !PhotoFileType.isRAW(URL(fileURLWithPath: $0.primaryPath)) }.count : 0
        return RecipeSyncTransaction(sourceID: sourceID, changes: changes, skippedRAWCount: skipped)
    }
    /// Compare every target before restoring any of them. Later edits must never be lost.
    public func undoSynchronization(_ transaction: RecipeSyncTransaction) throws {
        let targets = try photos(matching: Set(transaction.changes.map(\.id)))
        var updates = [(StoredPhoto, Data)]()
        for change in transaction.changes {
            guard let photo = targets.first(where: { $0.id == change.id }), try decodedRecipe(photo) == change.after else {
                throw LumaError.unsupported("同步后有照片被再次编辑，无法整组撤回。请保留后续修改，使用单张编辑调整。")
            }
            updates.append((photo, try change.before.json()))
        }
        for (photo, data) in updates { photo.recipeData = data }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    private func decodedRecipe(_ photo: StoredPhoto) throws -> Recipe {
        guard let data = photo.recipeData else { return Recipe() }
        return try JSONDecoder().decode(Recipe.self, from: data).validated()
    }
    private func photos(matching ids: Set<UUID>) throws -> [StoredPhoto] {
        let result = try context.fetch(FetchDescriptor<StoredPhoto>()).filter { ids.contains($0.id) }
        guard result.count == ids.count else { throw LumaError.corruptData("所选照片已不在当前图库，请刷新后重试") }
        return result
    }
    public func storeRecipe(_ recipe: Recipe, named name: String) throws -> URL {
        let url = root.appendingPathComponent("Recipes/\(Self.safeName(name)).json")
        try recipe.json().write(to: url, options: [.atomic]); return url
    }
    public static func safeName(_ name: String) -> String {
        let n = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        return String(n.prefix(80)).isEmpty ? "recipe" : String(n.prefix(80))
    }
}
