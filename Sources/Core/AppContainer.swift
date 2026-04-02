import Foundation
import AVFoundation

/// 依赖注入容器 - 集中管理应用所有依赖对象
/// 解决单例难以测试的问题，便于单元测试时替换为 mock 对象
final class AppContainer {

    // MARK: - 核心服务

    /// 网络管理器
    let networkManager: NetworkManager

    /// Jellyfin API
    let jellyfinAPI: JellyfinAPIClient

    // MARK: - 播放器相关

    /// 播放器复用池
    let playerPool: PlayerPool

    /// 视频缓存
    let videoCache: VideoCache

    /// 图片缓存（协议类型，支持注入 mock）
    let imageCache: ImageCacheProtocol

    /// 播放器预加载器
    let playerPreloader: PlayerPreloader

    // MARK: - 验证器

    /// URL 验证器
    let urlValidator: URLValidatorProtocol

    // MARK: - 监控

    /// 网络状态监控（协议类型，支持注入 mock）
    let networkMonitor: NetworkMonitorProtocol

    // MARK: - Token 刷新

    /// Token 刷新拦截器（用于 401 时自动刷新）
    private(set) var tokenRefreshInterceptor: TokenRefreshInterceptor?

    // MARK: - 初始化

    /// 初始化容器（支持依赖注入，便于单元测试）
    /// - Parameters:
    ///   - networkManager: 网络管理器，默认使用共享实例
    ///   - jellyfinAPI: 可选的 JellyfinAPI，用于注入 mock 对象
    ///   - playerPool: 播放器池，默认使用共享实例
    ///   - videoCache: 视频缓存，默认使用共享实例
    ///   - imageCache: 图片缓存，默认使用共享实例
    ///   - networkMonitor: 网络监控，默认使用共享实例
    init(
        networkManager: NetworkManager = .shared,
        jellyfinAPI: JellyfinAPIClient? = nil,
        playerPool: PlayerPool = .shared,
        videoCache: VideoCache = .shared,
        imageCache: ImageCacheProtocol = ImageCache.shared,
        networkMonitor: NetworkMonitorProtocol = NetworkMonitor.shared
    ) {
        self.networkManager = networkManager

        // 初始化 Jellyfin API（支持注入 mock）
        if let api = jellyfinAPI {
            self.jellyfinAPI = api
        } else {
            self.jellyfinAPI = JellyfinAPI(networkService: networkManager)
        }

        // 播放器相关（支持注入 mock）
        self.playerPool = playerPool
        self.videoCache = videoCache
        self.imageCache = imageCache
        self.playerPreloader = PlayerPreloader()

        // 验证器
        self.urlValidator = DefaultURLValidator()

        // 监控
        self.networkMonitor = networkMonitor

        Logger.info("AppContainer initialized")
    }

    // MARK: - Token 刷新配置

    /// 配置 Token 刷新拦截器
    /// - Parameters:
    ///   - refreshToken: 刷新 Token 的异步闭包
    ///   - updateToken: 更新 Token 的闭包
    func configureTokenRefresh(
        refreshToken: @escaping () async -> Bool,
        updateToken: @escaping (String) -> Void
    ) {
        tokenRefreshInterceptor = TokenRefreshInterceptor(
            refreshToken: refreshToken,
            updateToken: updateToken
        )

        // 将刷新拦截器添加到拦截器链中
        if let refreshInterceptor = tokenRefreshInterceptor {
            networkManager.prependInterceptor(refreshInterceptor)
            Logger.info("Token refresh interceptor configured")
        }
    }
}

// MARK: - 单例便捷访问

extension AppContainer {
    /// 全局容器实例
    static var shared = AppContainer()
}
