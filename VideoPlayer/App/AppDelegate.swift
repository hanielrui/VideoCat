import UIKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 配置音频会话（后台播放支持）
        configureAudioSession()

        // 初始化日志
        Logger.info("Application launched")

        window = UIWindow(frame: UIScreen.main.bounds)

        // 设置导航栏样式
        let nav = UINavigationController(rootViewController: LoginViewController())
        nav.navigationBar.prefersLargeTitles = true
        window?.rootViewController = nav
        window?.makeKeyAndVisible()

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
