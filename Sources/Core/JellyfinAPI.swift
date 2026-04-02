import Foundation

// MARK: - API 错误

/// Jellyfin API 相关错误类型
enum JellyfinError: LocalizedError {
    case notLoggedIn
    case invalidResponse
    case playbackURLFailed
    case invalidCredentials
    case serverUnreachable
    case mediaUnavailable
    case playbackFailed(underlying: Error?)

    // MARK: - 统一属性

    /// 错误分类
    var category: NetworkErrorCategory {
        switch self {
        case .notLoggedIn, .invalidCredentials:
            return .auth
        case .serverUnreachable:
            return .network
        case .mediaUnavailable, .playbackURLFailed:
            return .server
        case .invalidResponse, .playbackFailed:
            return .unknown
        }
    }

    /// 是否可重试
    var isRetryable: Bool {
        switch self {
        case .serverUnreachable, .mediaUnavailable, .playbackURLFailed:
            return true
        case .playbackFailed(let underlying):
            // 如果底层是网络错误则可重试
            if let networkError = underlying as? NetworkError {
                return networkError.isRetryable
            }
            return false
        default:
            return false
        }
    }

    /// 是否需要登出
    var shouldLogout: Bool {
        switch self {
        case .notLoggedIn, .invalidCredentials:
            return true
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Please login first"
        case .invalidResponse:
            return "Invalid server response"
        case .playbackURLFailed:
            return "Failed to get playback URL"
        case .invalidCredentials:
            return "Invalid username or password"
        case .serverUnreachable:
            return "Cannot connect to server"
        case .mediaUnavailable:
            return "Media file is unavailable"
        case .playbackFailed(let underlying):
            if let error = underlying {
                return "Playback failed: \(error.localizedDescription)"
            }
            return "Playback failed"
        }
    }

    /// 恢复建议
    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials:
            return "Please check your Jellyfin username and password"
        case .serverUnreachable:
            return "1. Check your network connection\n2. Verify server address\n3. Ensure server is running"
        case .mediaUnavailable:
            return "Try refreshing the list or select another media"
        case .playbackFailed:
            return "Check network or try playing again"
        default:
            return nil
        }
    }
}

/// 登录验证错误
enum LoginValidationError: LocalizedError {
    case invalidInput(String)
    case emptyField(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .emptyField(let field):
            return "\(field) cannot be empty"
        }
    }

    var category: NetworkErrorCategory {
        return .client
    }

    var isRetryable: Bool {
        return false
    }

    var shouldLogout: Bool {
        return false
    }
}

// MARK: - Jellyfin API 协议

/// Jellyfin API 客户端接口协议，便于单元测试 mock
protocol JellyfinAPIClient: AnyObject {
    /// 是否已登录
    var isLoggedIn: Bool { get }

    /// 当前认证 Token
    var token: String { get set }

    /// 服务器基础 URL
    var baseURL: String { get set }

    /// 用户登录
    func login(username: String, password: String) async throws

    /// 用户登出
    func logout()

    /// 获取媒体列表
    func fetchItems() async throws -> [MediaItem]

    /// 获取播放地址
    func getPlayURL(itemId: String) -> String?

    /// 刷新 Token（需要服务器支持）
    /// - Returns: 是否刷新成功
    func refreshToken() async -> Bool
}

// MARK: - 登录信息持久化键
private enum StorageKeys {
    static let userId = "jellyfin_user_id"
    static let userName = "jellyfin_user_name"
    static let baseURL = "jellyfin_base_url"
}

// MARK: - Jellyfin API

/// Jellyfin API 客户端实现
class JellyfinAPI: JellyfinAPIClient {

    // MARK: - 单例（保持向后兼容）
    static let shared = JellyfinAPI()

    // MARK: - 可注入属性
    private var networkService: NetworkService

    // 内部 API 服务（用于解耦业务逻辑）
    private var apiService: JellyfinAPIService?

    // MARK: - 用户状态
    private(set) var userId: String = "" {
        didSet {
            UserDefaults.standard.set(userId, forKey: StorageKeys.userId)
        }
    }
    private(set) var userName: String = "" {
        didSet {
            UserDefaults.standard.set(userName, forKey: StorageKeys.userName)
        }
    }

    var isLoggedIn: Bool {
        !userId.isEmpty && !token.isEmpty
    }

    // Token 存储（使用 Keychain 安全性更高）
    var token: String {
        get {
            do {
                return try KeychainManager.get(key: KeychainManager.tokenKey)
            } catch {
                Logger.error("Failed to get token from Keychain: \(error)")
                return ""
            }
        }
        set {
            if newValue.isEmpty {
                do {
                    try KeychainManager.delete(key: KeychainManager.tokenKey)
                } catch {
                    Logger.error("Failed to delete token from Keychain: \(error)")
                }
            } else {
                do {
                    try KeychainManager.save(key: KeychainManager.tokenKey, value: newValue)
                } catch {
                    Logger.error("Failed to save token to Keychain: \(error)")
                }
            }
            // 同步到 NetworkService（通过协议属性）
            networkService.token = newValue
        }
    }

    // BaseURL 持久化
    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: StorageKeys.baseURL) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: StorageKeys.baseURL)
            // 同步到 NetworkService（通过协议属性）
            networkService.baseURL = newValue
        }
    }

    // MARK: - 初始化方法

    // 默认初始化（使用共享 NetworkManager）
    init() {
        self.networkService = NetworkManager.shared
        self.apiService = JellyfinAPIService(networkService: networkService)
        loadStoredCredentials()
    }

    // 可注入初始化（便于单元测试）
    init(networkService: NetworkService) {
        self.networkService = networkService
        self.apiService = JellyfinAPIService(networkService: networkService)
    }

    // MARK: - 加载持久化的登录信息
    private func loadStoredCredentials() {
        userId = UserDefaults.standard.string(forKey: StorageKeys.userId) ?? ""
        userName = UserDefaults.standard.string(forKey: StorageKeys.userName) ?? ""

        // 从 Keychain 加载 token
        var storedToken = ""
        do {
            storedToken = try KeychainManager.get(key: KeychainManager.tokenKey)
        } catch {
            Logger.error("Failed to load token from Keychain: \(error)")
        }

        // 同步到 NetworkService（通过协议属性）
        networkService.token = storedToken
        if let storedBaseURL = UserDefaults.standard.string(forKey: StorageKeys.baseURL), !storedBaseURL.isEmpty {
            networkService.baseURL = storedBaseURL
        }

        if !userId.isEmpty && !storedToken.isEmpty {
            Logger.info("Restored login session for user: \(userName)")
        }
    }

    // MARK: - 登录
    func login(username: String, password: String) async throws {
        Logger.Auth.loginAttempt(username)

        // 使用 apiService 处理认证
        guard let apiService = apiService else {
            Logger.error("API service not initialized")
            throw JellyfinError.invalidResponse
        }

        do {
            let response = try await apiService.authenticate(username: username, password: password)

            // 保存 token 和用户信息（通过 setter 持久化）
            token = response.accessToken
            userId = response.user.id
            userName = response.user.name

            Logger.Auth.loginSuccess(username)
        } catch let error as NetworkError {
            // 映射网络错误到 Jellyfin 错误
            throw mapNetworkError(error)
        }
    }

    // MARK: - 网络错误映射
    private func mapNetworkError(_ error: NetworkError) -> JellyfinError {
        if case .serverError(let code, _) = error {
            switch code {
            case 401:
                Logger.warning("Request failed: invalid credentials")
                return .invalidCredentials
            case 403:
                Logger.warning("Request failed: access forbidden")
                return .invalidCredentials
            case 404:
                Logger.warning("Request failed: not found")
                return .serverUnreachable
            case 500...599:
                Logger.warning("Request failed: server error \(code)")
                return .serverUnreachable
            default:
                Logger.error("Request failed: HTTP \(code)")
                return .invalidResponse
            }
        }
        if case .noNetwork = error {
            Logger.warning("Request failed: no network")
            return .serverUnreachable
        }
        if case .timeout = error {
            Logger.warning("Request failed: timeout")
            return .serverUnreachable
        }
        Logger.error("Request failed: \(error.localizedDescription)")
        return .invalidResponse
    }

    // MARK: - 登出
    func logout() {
        userId = ""
        userName = ""
        token = "" // token setter 会同步清除 Keychain 和 NetworkManager

        // 清除持久化信息
        UserDefaults.standard.removeObject(forKey: StorageKeys.userId)
        UserDefaults.standard.removeObject(forKey: StorageKeys.userName)
        UserDefaults.standard.removeObject(forKey: StorageKeys.baseURL)

        Logger.Auth.logout()
    }

    // MARK: - 获取媒体列表
    func fetchItems() async throws -> [MediaItem] {
        // 防御性检查
        guard !userId.isEmpty else {
            Logger.warning("Fetch items failed: userId is empty")
            throw JellyfinError.notLoggedIn
        }

        guard isLoggedIn else {
            Logger.warning("Fetch items failed: not logged in")
            throw JellyfinError.notLoggedIn
        }

        // 使用 apiService 获取媒体
        guard let apiService = apiService else {
            throw JellyfinError.invalidResponse
        }

        do {
            let items = try await apiService.fetchItems(
                userId: userId,
                recursive: true,
                includeItemTypes: APIConstants.MediaTypes.all
            )

            Logger.info("Fetched \(items.count) items")
            return items
        } catch let error as NetworkError {
            // 使用公共错误映射方法
            if case .serverError(let code, _) = error, code == 401 {
                // 401 需要额外清理登录状态
                logout()
            }
            throw mapNetworkError(error)
        }
    }

    // MARK: - 获取播放 URL
    func getPlayURL(itemId: String) -> String? {
        guard isLoggedIn, !itemId.isEmpty else {
            Logger.warning("Invalid playback URL request: not logged in or empty itemId")
            return nil
        }

        // 使用 apiService 构建播放 URL
        guard let apiService = apiService,
              let url = apiService.buildPlaybackURL(itemId: itemId, apiKey: token) else {
            Logger.error("Failed to build media URL for item: \(itemId)")
            return nil
        }

        Logger.Player.play(url: url.absoluteString)

        return url.absoluteString
    }

    // MARK: - Token 刷新
    /// 刷新访问令牌
    /// 注意：Jellyfin API 默认不支持 refresh token，需要服务器启用此功能
    /// 如果服务器不支持，调用此方法将返回 false
    func refreshToken() async -> Bool {
        // Jellyfin 服务器默认使用 AccessToken + UserId 进行认证
        // 不像 OAuth 那样有独立的 refresh token 机制
        // 如果 token 过期，用户需要重新登录
        Logger.warning("Token refresh requested but Jellyfin API does not support refresh token by default")
        Logger.info("User will need to re-login when token expires")

        // 方案1: 如果 Jellyfin 服务器启用了 "Enable automatic token refresh"
        // 可以通过重新认证来刷新 token（使用已保存的凭据）
        // 方案2: 在服务器端配置更长的 token 过期时间
        // 方案3: 用户重新登录

        return false
    }
}
