import Foundation

// MARK: - Token 拦截器

/// Token 拦截器
/// 自动在请求头中注入认证 Token
final class TokenInterceptor: NetworkInterceptor {

    // MARK: - 属性

    /// Token 提供者闭包
    private let tokenProvider: () -> String

    /// Token 键名（请求头名称）
    private let tokenKey: String

    // MARK: - 初始化

    /// 初始化 Token 拦截器
    /// - Parameters:
    ///   - tokenProvider: Token 提供闭包
    ///   - tokenKey: 请求头键名，默认为 "X-Emby-Token"
    init(tokenProvider: @escaping () -> String, tokenKey: String = APIConstants.Headers.token) {
        self.tokenProvider = tokenProvider
        self.tokenKey = tokenKey
    }

    // MARK: - NetworkInterceptor

    /// 请求适配：自动注入 Token
    func adapt(_ request: URLRequest) async -> URLRequest {
        var adaptedRequest = request

        // 获取当前 Token
        let token = tokenProvider()

        // 只有非空 Token 才注入
        if !token.isEmpty {
            adaptedRequest.setValue(token, forHTTPHeaderField: tokenKey)
            Logger.debug("Token added to request: \(tokenKey)")
        } else {
            Logger.debug("No token available, request sent without auth header")
        }

        return adaptedRequest
    }

    /// 错误拦截：检查 Token 相关错误
    func retry(_ request: URLRequest, error: Error) async -> Bool {
        // 将错误转换为 NetworkError 检查
        guard let networkError = error as? NetworkError else {
            return false
        }

        // 检查是否是 401 未授权错误
        if case .serverError(let statusCode, _) = networkError, statusCode == 401 {
            Logger.warning("Received 401 Unauthorized, token may be invalid")
            // 注意：不自动重试的原因：
            // 1. Jellyfin API 默认不支持 refresh token
            // 2. 刷新失败后需要用户重新登录，这是关键安全操作
            // 3. 401 错误由上层（AppCoordinator）处理，它会触发登出流程
            // 如果需要自动刷新 Token，可以使用已配置的 TokenRefreshInterceptor
            return false
        }

        return false
    }
}

// MARK: - Token 刷新拦截器（可选扩展）

/// Token 刷新拦截器（可选功能）
/// 当收到 401 错误时自动尝试刷新 Token
final class TokenRefreshInterceptor: NetworkInterceptor {

    // MARK: - 属性

    /// Token 刷新闭包
    private let refreshToken: () async -> Bool

    /// 刷新后的 Token 更新闭包
    private let updateToken: (String) -> Void

    /// 是否正在刷新（防止并发刷新）
    private var isRefreshing = false

    // MARK: - 初始化

    /// 初始化 Token 刷新拦截器
    /// - Parameters:
    ///   - refreshToken: 刷新 Token 的异步闭包，返回是否成功
    ///   - updateToken: 更新 Token 的闭包
    init(refreshToken: @escaping () async -> Bool, updateToken: @escaping (String) -> Void) {
        self.refreshToken = refreshToken
        self.updateToken = updateToken
    }

    // MARK: - NetworkInterceptor

    /// 请求适配：不做额外处理
    func adapt(_ request: URLRequest) async -> URLRequest {
        request
    }

    /// 错误拦截：尝试刷新 Token
    func retry(_ request: URLRequest, error: Error) async -> Bool {
        guard let networkError = error as? NetworkError else {
            return false
        }

        // 只处理 401 错误
        if case .serverError(let statusCode, _) = networkError, statusCode == 401 {
            // 防止并发刷新
            guard !isRefreshing else {
                Logger.debug("Token refresh already in progress, skipping")
                return false
            }

            isRefreshing = true
            defer { isRefreshing = false }

            Logger.info("Attempting to refresh token...")

            // 尝试刷新 Token
            let success = await refreshToken()

            if success {
                Logger.info("Token refreshed successfully")
                return true // 返回 true 表示可以重试
            } else {
                Logger.warning("Token refresh failed")
                return false
            }
        }

        return false
    }
}