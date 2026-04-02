import Foundation

// MARK: - 登录响应
struct LoginResponse: Codable {
    let accessToken: String
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        user = try container.decodeIfPresent(User.self, forKey: .user) ?? User(id: "", name: "")
    }

    init(accessToken: String, user: User) {
        self.accessToken = accessToken
        self.user = user
    }
}

struct User: Codable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - 媒体列表响应
struct JellyfinItemsResponse: Codable {
    let items: [MediaItem]
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([MediaItem].self, forKey: .items) ?? []
        totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount)
    }

    init(items: [MediaItem], totalRecordCount: Int? = nil) {
        self.items = items
        self.totalRecordCount = totalRecordCount
    }
}

struct MediaItem: Codable {
    let id: String
    let name: String
    let type: String?
    let thumbnail: String?
    let overview: String?
    let productionYear: Int?
    let runTimeTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case thumbnail = "ThumbnailImageTag"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        type = try container.decodeIfPresent(String.self, forKey: .type)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        productionYear = try container.decodeIfPresent(Int.self, forKey: .productionYear)
        runTimeTicks = try container.decodeIfPresent(Int64.self, forKey: .runTimeTicks)
    }

    init(id: String, name: String, type: String? = nil, thumbnail: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.thumbnail = thumbnail
        self.overview = nil
        self.productionYear = nil
        self.runTimeTicks = nil
    }

    // 计算属性：运行时长（秒）
    var runTimeSeconds: Int? {
        guard let ticks = runTimeTicks else { return nil }
        return Int(ticks / 10_000_000)
    }
}
