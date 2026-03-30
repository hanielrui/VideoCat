import Foundation

// MARK: - API 错误
enum JellyfinError: LocalizedError {
    case notLoggedIn
    case invalidResponse
    case playbackURLFailed
    case invalidCredentials
    case serverUnreachable
    case mediaUnavailable
    case playbackFailed(underlying: Error?)

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

    // 恢复建议
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

// MARK: - Jellyfin API 协议（便于单元测试 mock）
protocol JellyfinAPIProtocol {
    var isLoggedIn: Bool { get }
    func login(username: String, password: String) async throws
    func logout()
    func fetchItems() async throws -> [MediaItem]
    func getPlayURL(itemId: String) -> String?
}

// MARK: - 登录信息持久化键
private enum StorageKeys {
    static let userId = "jellyfin_user_id"
    static let userName = "jellyfin_user_name"
    static let baseURL = "jellyfin_base_url"
}

// MARK: - Jellyfin API
class JellyfinAPI: JellyfinAPIProtocol {

    // MARK: - 单例（保持向后兼容）
    static let shared = JellyfinAPI()

    // MARK: - 可注入属性
    private var networkService: NetworkServiceProtocol

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

    // Token 存储（同步到 UserDefaults）
    private var token: String {
        get {
            UserDefaults.standard.string(forKey: "jellyfin_token") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "jellyfin_token")
        }
    }

    // BaseURL 持久化
    var baseURL: String {
        get {
            UserDefaults.standard.string(forKey: StorageKeys.baseURL) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: StorageKeys.baseURL)
            if let manager = networkService as? NetworkManager {
                manager.baseURL = newValue
            }
        }
    }

    // MARK: - 初始化方法

    // 默认初始化（使用共享 NetworkManager）
    init() {
        self.networkService = NetworkManager.shared
        loadStoredCredentials()
    }

    // 可注入初始化（便于单元测试）
    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    // MARK: - 加载持久化的登录信息
    private func loadStoredCredentials() {
        userId = UserDefaults.standard.string(forKey: StorageKeys.userId) ?? ""
        userName = UserDefaults.standard.string(forKey: StorageKeys.userName) ?? ""
        let storedToken = UserDefaults.standard.string(forKey: "jellyfin_token") ?? ""

        if let manager = networkService as? NetworkManager {
            manager.token = storedToken
            if let storedBaseURL = UserDefaults.standard.string(forKey: StorageKeys.baseURL), !storedBaseURL.isEmpty {
                manager.baseURL = storedBaseURL
            }
        }

        if !userId.isEmpty && !storedToken.isEmpty {
            Logger.info("Restored login session for user: \(userName)")
        }
    }

    // MARK: - 登录
    func login(username: String, password: String) async throws {
        Logger.Auth.loginAttempt(username)

        let body: [String: Any] = [
            "Username": username,
            "Pw": password
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            Logger.error("Failed to serialize login body")
            throw JellyfinError.invalidResponse
        }

        var config = RequestConfig()
        config.contentType = APIConstants.ContentType.json

        // 直接使用 NetworkManager 以访问 token
        guard let manager = networkService as? NetworkManager else {
            throw JellyfinError.invalidResponse
        }

        do {
            let response: LoginResponse = try await manager.request(
                path: APIConstants.Endpoints.authenticate,
                method: "POST",
                body: bodyData,
                config: config
            )

            // 保存 token 和用户信息（已自动持久化）
            manager.token = response.accessToken
            token = response.accessToken  // 确保持久化
            userId = response.user.id
            userName = response.user.name

            Logger.Auth.loginSuccess(username)
        } catch let error as NetworkError {
            if case .httpError(let code) = error {
                // 详细的 HTTP 错误码映射
                switch code {
                case 401:
                    Logger.warning("Login failed: invalid credentials")
                    throw JellyfinError.invalidCredentials
                case 403:
                    Logger.warning("Login failed: access forbidden")
                    throw JellyfinError.invalidCredentials
                case 404:
                    Logger.warning("Login failed: server not found")
                    throw JellyfinError.serverUnreachable
                case 500...599:
                    Logger.warning("Login failed: server error \(code)")
                    throw JellyfinError.serverUnreachable
                default:
                    Logger.error("Login failed: HTTP \(code)")
                    throw JellyfinError.invalidResponse
                }
            }
            if case .noNetwork = error {
                Logger.warning("Login failed: server unreachable")
                throw JellyfinError.serverUnreachable
            }
            if case .timeout = error {
                Logger.warning("Login failed: request timeout")
                throw JellyfinError.serverUnreachable
            }
            Logger.error("Login failed: \(error.localizedDescription)")
            throw JellyfinError.invalidResponse
        }
    }

    // MARK: - 登出
    func logout() {
        userId = ""
        userName = ""
        token = ""

        if let manager = networkService as? NetworkManager {
            manager.token = ""
        }

        // 清除持久化信息
        UserDefaults.standard.removeObject(forKey: StorageKeys.userId)
        UserDefaults.standard.removeObject(forKey: StorageKeys.userName)
        UserDefaults.standard.removeObject(forKey: "jellyfin_token")
        UserDefaults.standard.removeObject(forKey: StorageKeys.baseURL)

        Logger.Auth.logout()
    }

    // MARK: - 获取媒体列表
    func fetchItems() async throws -> [MediaItem] {
        // 防御性检查：userId 不能为空
        guard !userId.isEmpty else {
            Logger.warning("Fetch items failed: userId is empty")
            throw JellyfinError.notLoggedIn
        }

        guard isLoggedIn else {
            Logger.warning("Fetch items failed: not logged in")
            throw JellyfinError.notLoggedIn
        }

        let path = String(format: APIConstants.Endpoints.items, userId) +
            "?\(APIConstants.QueryParams.recursive)=true" +
            "&\(APIConstants.QueryParams.includeItemTypes)=\(APIConstants.MediaTypes.all)"

        Logger.debug("Fetching items from: \(path)")

        guard let manager = networkService as? NetworkManager else {
            throw JellyfinError.invalidResponse
        }

        do {
            let response: JellyfinItemsResponse = try await manager.request(path: path)

            Logger.info("Fetched \(response.items.count) items")

            return response.items
        } catch let error as NetworkError {
            if case .httpError(let code) = error {
                switch code {
                case 401:
                    // Token 过期，清除登录状态
                    logout()
                    throw JellyfinError.notLoggedIn
                case 403:
                    throw JellyfinError.mediaUnavailable
                case 404:
                    throw JellyfinError.mediaUnavailable
                case 500...599:
                    throw JellyfinError.serverUnreachable
                default:
                    throw JellyfinError.invalidResponse
                }
            }
            if case .noNetwork = error {
                throw JellyfinError.serverUnreachable
            }
            if case .timeout = error {
                throw JellyfinError.serverUnreachable
            }
            throw JellyfinError.invalidResponse
        }
    }

    // MARK: - 获取播放 URL
    func getPlayURL(itemId: String) -> String? {
        guard isLoggedIn, !itemId.isEmpty else {
            Logger.warning("Invalid playback URL request: not logged in or empty itemId")
            return nil
        }

        guard let manager = networkService as? NetworkManager else {
            return nil
        }

        // 使用 URLBuilder 构建 URL，正确处理特殊字符
        guard let url = manager.urlBuilder.buildMediaURL(
            itemId: itemId,
            apiKey: token
        ) else {
            Logger.error("Failed to build media URL for item: \(itemId)")
            return nil
        }

        Logger.Player.play(url: url.absoluteString)

        return url.absoluteString
    }
}
