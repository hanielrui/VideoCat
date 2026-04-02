import UIKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// 应用协调器
    private var appCoordinator: AppCoordinator?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 配置音频会话（后台播放支持）
        configureAudioSession()

        // 初始化日志
        Logger.info("Application launched")

        // 创建窗口
        window = UIWindow(frame: UIScreen.main.bounds)

        // 创建导航控制器
        let navigationController = UINavigationController()
        navigationController.navigationBar.prefersLargeTitles = true

        // 创建应用协调器（使用全局容器实例）
        let container = AppContainer.shared
        appCoordinator = AppCoordinator(
            navigationController: navigationController,
            container: container
        )

        // 配置 Token 刷新拦截器
        // 为了避免潜在的循环引用，使用本地变量捕获 jellyfinAPI
        let jellyfinAPI = container.jellyfinAPI
        let networkManager = container.networkManager
        
        container.configureTokenRefresh(
            refreshToken: { [weak jellyfinAPI] in
                // 通过协议调用 JellyfinAPI 的 refreshToken 方法
                guard let jellyfinAPI = jellyfinAPI else { return false }
                return await jellyfinAPI.refreshToken()
            },
            updateToken: { [weak networkManager] newToken in
                // 更新 NetworkService 的 token（通过协议属性）
                networkManager?.token = newToken
                Logger.info("Token updated in NetworkManager")
            }
        )

        // 启动协调器
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        appCoordinator?.start()

        return true
    }

    // MARK: - 音频会话配置
    private func configureAudioSession() {
        do {
            // 设置播放模式（退后台会自动暂停）
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            Logger.info("Audio session configured")
        } catch {
            Logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - 应用进入后台
    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.debug("Application entered background")
    }

    // MARK: - 应用进入前台
    func applicationWillEnterForeground(_ application: UIApplication) {
        Logger.debug("Application will enter foreground")
    }

    // MARK: - 全局异常捕获
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
