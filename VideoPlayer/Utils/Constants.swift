import Foundation

// MARK: - API 常量
enum APIConstants {

    // MARK: - HTTP Headers
    enum Headers {
        static let token = "X-Emby-Token"
        static let contentType = "Content-Type"
        static let authorization = "Authorization"
    }

    // MARK: - Content Types
    enum ContentType {
        static let json = "application/json"
        static let formData = "multipart/form-data"
        static let urlEncoded = "application/x-www-form-urlencoded"
    }

    // MARK: - API 路径
    enum Endpoints {
        // 认证
        static let authenticate = "/Users/AuthenticateByName"

        // 媒体
        static let items = "/Users/%@/Items"
        static let videoStream = "/Videos/%@/stream.m3u8"
        static let mediaInfo = "/Items/%@/Info"
    }

    // MARK: - 查询参数
    enum QueryParams {
        static let recursive = "Recursive"
        static let includeItemTypes = "IncludeItemTypes"
        static let apiKey = "api_key"
    }

    // MARK: - 媒体类型
    enum MediaTypes {
        static let movie = "Movie"
        static let episode = "Episode"
        static let series = "Series"

        static let all = [movie, episode].joined(separator: ",")
    }
}

// MARK: - App 常量
enum AppConstants {

    // MARK: - 超时设置
    enum Timeout {
        static let defaultRequest: TimeInterval = 30
        static let mediaLoad: TimeInterval = 60
    }

    // MARK: - UI 常量
    enum UI {
        static let animationDuration: TimeInterval = 0.3
        static let cornerRadius: CGFloat = 8
        static let spacing: CGFloat = 12
        static let padding: CGFloat = 16
    }

    // MARK: - 手势配置
    enum Gesture {
        static let directionThreshold: CGFloat = 10
        static let seekSensitivity: CGFloat = 200  // 滑动多少点触发一次 seek
        static let volumeSensitivity: CGFloat = 300
    }

    // MARK: - 用户默认键
    enum UserDefaultsKeys {
        static let serverURL = "jellyfin_server_url"
        static let username = "jellyfin_username"
        static let token = "jellyfin_token"
        static let userId = "jellyfin_user_id"
    }
}
