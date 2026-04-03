import UIKit

/// 应用级别的导航协调器 - 负责整个应用的页面导航流程
final class AppCoordinator: AppCoordinatorProtocol {

    // MARK: - 属性

    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController

    // MARK: - 依赖注入容器

    private let container: AppContainer

    // MARK: - 初始化

    init(navigationController: UINavigationController, container: AppContainer) {
        self.navigationController = navigationController
        self.container = container
    }

    // MARK: - Coordinator

    func start() {
        // 根据登录状态决定首页
        if container.jellyfinAPI.isLoggedIn {
            navigateToHome()
        } else {
            navigateToLogin()
        }
    }

    // MARK: - 导航操作 (NavigationActionHandler)

    func pop() {
        navigationController.popViewController(animated: true)
    }

    func popToRoot() {
        navigationController.popToRootViewController(animated: true)
    }

    func popTo(_ viewController: UIViewController) {
        navigationController.popToViewController(viewController, animated: true)
    }

    func present(_ viewController: UIViewController, animated: Bool = true) {
        navigationController.present(viewController, animated: animated)
    }

    func presentAlert(title: String?, message: String?, actions: [UIAlertAction]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach { alert.addAction($0) }
        navigationController.present(alert, animated: true)
    }

    func dismiss() {
        navigationController.dismiss(animated: true)
    }

    func push(_ viewController: UIViewController, animated: Bool = true) {
        navigationController.pushViewController(viewController, animated: animated)
    }

    // MARK: - 页面导航

    @MainActor
    func navigateToLogin() {
        // 清除用户数据
        container.jellyfinAPI.logout()

        Task { [weak self] in
            await self?.container.playerPool.clearPool()
        }

        let loginVC = LoginViewController()
        loginVC.coordinator = self
        navigationController.setViewControllers([loginVC], animated: true)

        Logger.Navigation.navigateToLogin()
    }

    @MainActor
    func navigateToHome() {
        let homeVC = JellyfinHomeViewController()
        homeVC.coordinator = self
        navigationController.pushViewController(homeVC, animated: true)

        Logger.Navigation.navigateToHome()
    }

    func navigateToPlayer(with url: String) {
        // 使用 URL 直接初始化 PlayerViewController
        // 从播放器池获取播放器实例，避免重复创建
        Task { @MainActor in
            // 从播放器池获取播放器实例
            let player = await container.playerPool.acquirePlayer()

            // 确保播放器符合 PlayerEngineProtocol（PlayerEngine 实例符合）
            let engine: PlayerEngineProtocol
            if let playerEngine = player as? PlayerEngineProtocol {
                engine = playerEngine
                Logger.debug("Player acquired from pool")
            } else {
                // 回退：创建新的 PlayerEngine（理论上不会发生）
                engine = PlayerEngine()
                Logger.warning("Player from pool is not PlayerEngineProtocol, created new instance")
            }

            let viewModel = PlayerViewModel(engine: engine)
            let playerVC = PlayerViewController(
                viewModel: viewModel,
                gestureManager: nil,
                urlValidator: container.urlValidator,
                url: url
            )
            playerVC.coordinator = self
            playerVC.player = player // 保存引用以便在 deinit 中归还

            navigationController.pushViewController(playerVC, animated: true)

            Logger.Navigation.navigateToPlayer(url: url)
        }
    }

    func navigateToPlayer(with item: MediaItem) {
        // 通过依赖注入获取播放 URL
        guard let urlString = container.jellyfinAPI.getPlayURL(itemId: item.id),
              let _ = URL(string: urlString) else {
            Logger.error("Failed to build playback URL for item: \(item.id)")
            return
        }

        navigateToPlayer(with: urlString)
    }

    func logout() {
        Task { [weak self] in
            await self?.container.playerPool.clearPool()
        }

        // 返回登录页
        navigateToLogin()

        Logger.Auth.logout()
    }

    /// 播放器使用完毕后归还到池中
    func releasePlayer(_ player: PlayerCoreProtocol) {
        Task { [weak self] in
            // PlayerCoreProtocol 继承自 Player，可以直接传递
            await self?.container.playerPool.releasePlayer(player as Player)
        }
    }
}
