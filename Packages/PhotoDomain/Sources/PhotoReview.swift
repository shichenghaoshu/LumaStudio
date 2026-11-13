import Foundation

public enum PhotoFlag: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, picked, rejected
    public var id: Self { self }
    public var title: String { switch self { case .none: return "未标记"; case .picked: return "入选"; case .rejected: return "淘汰" } }
    public var symbol: String { switch self { case .none: return "flag"; case .picked: return "flag.fill"; case .rejected: return "xmark.circle" } }
}

public enum PhotoColorLabel: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, red, yellow, green, blue, purple
    public var id: Self {self}
    public var title: String {
        switch self {
        case .none: return "无色标"
        case .red: return "红色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        }
    }
}

public struct PhotoReview: Codable, Equatable, Sendable {
    public var rating: Int
    public var flag: PhotoFlag
    public var colorLabel: PhotoColorLabel
    public init(rating: Int = 0, flag: PhotoFlag = .none, colorLabel: PhotoColorLabel = .none) {
        self.rating = rating; self.flag = flag; self.colorLabel = colorLabel
    }
    private enum CodingKeys: String, CodingKey {case rating, flag, colorLabel}
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        rating=try c.decode(Int.self,forKey:.rating)
        flag=try c.decode(PhotoFlag.self,forKey:.flag)
        // Existing reviewData contains only rating and flag; no store migration is needed.
        colorLabel=try c.decodeIfPresent(PhotoColorLabel.self,forKey:.colorLabel) ?? .none
    }
    public func validated() throws -> Self {
        guard (0...5).contains(rating) else { throw LumaError.corruptData("星标需在 0–5 之间") }
        return self
    }
}

public enum PhotoFlagFilter: String, CaseIterable, Identifiable, Sendable {
    case all, unflagged, picked, rejected
    public var id: Self { self }
    public var title: String { switch self { case .all: return "全部旗标"; case .unflagged: return "未标记"; case .picked: return "仅入选"; case .rejected: return "仅淘汰" } }
    public func matches(_ flag: PhotoFlag) -> Bool {
        switch self { case .all: return true; case .unflagged: return flag == .none; case .picked: return flag == .picked; case .rejected: return flag == .rejected }
    }
}

public enum PhotoSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newest, name, rating
    public var id: Self { self }
    public var title: String { switch self { case .newest: return "最近导入"; case .name: return "文件名"; case .rating: return "星标优先" } }
}

public struct PhotoFilter: Equatable, Sendable {
    public var query = ""
    public var rawOnly = false
    public var minimumRating = 0
    public var flag: PhotoFlagFilter = .all
    /// nil means all labels; .some(.none) selects photos without a color label.
    public var colorLabel: PhotoColorLabel? = nil
    public var sort: PhotoSortOrder = .newest
    public init() {}
    public var isActive: Bool { !query.isEmpty || rawOnly || minimumRating > 0 || flag != .all || colorLabel != nil }
    public func apply(to assets: [PhotoAsset], reviews: [UUID: PhotoReview]) -> [PhotoAsset] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return assets.filter { asset in
            let review = reviews[asset.id] ?? PhotoReview()
            return (!rawOnly || asset.isRAW) && review.rating >= minimumRating && flag.matches(review.flag)
                && (colorLabel == nil || colorLabel == review.colorLabel)
                && (query.isEmpty || asset.name.localizedCaseInsensitiveContains(query))
        }.sorted { a, b in
            switch sort {
            case .newest: if a.importedAt != b.importedAt { return a.importedAt > b.importedAt }
            case .rating:
                let lhs = reviews[a.id]?.rating ?? 0, rhs = reviews[b.id]?.rating ?? 0
                if lhs != rhs { return lhs > rhs }
            case .name: break
            }
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id.uuidString < b.id.uuidString : order == .orderedAscending
        }
    }
}
