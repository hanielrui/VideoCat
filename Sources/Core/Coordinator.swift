import UIKit

// MARK: - Coordinator 协议

/// 导航协调器协议 - 负责应用导航流程管理
protocol Coordinator: AnyObject {
    /// 子协调器列表
    var childCoordinators: [Coordinator] { get set }
    
    /// 导航控制器
    var navigationController: UINavigationController { get set }
    
    /// 启动协调器
    func start()
}

extension Coordinator {
    /// 添加子协调器
    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
    }
    
    /// 移除子协调器
    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}

// MARK: - 导航操作协议

/// 导航操作协议 - 定义所有可能的导航行为
protocol NavigationActionHandler: AnyObject {
    /// 弹出当前视图控制器
    func pop()
    
    /// 弹出到根视图控制器
    func popToRoot()
    
    /// 弹出到指定视图控制器
    func popTo(_ viewController: UIViewController)
    
    /// 模态展示视图控制器
    func present(_ viewController: UIViewController, animated: Bool)
    
    /// 模态展示 alert
    func presentAlert(title: String?, message: String?, actions: [UIAlertAction])
    
    /// 解散模态视图控制器
    func dismiss()
    
    /// 导航到下一个视图控制器
    func push(_ viewController: UIViewController, animated: Bool)
}

// MARK: - AppCoordinator 协议

/// 应用级别协调器协议
protocol AppCoordinatorProtocol: Coordinator, NavigationActionHandler {
    /// 导航到登录页面
    func navigateToLogin()
    
    /// 导航到首页
    func navigateToHome()
    
    /// 导航到播放器
    func navigateToPlayer(with url: String)
    
    /// 导航到播放器（带 MediaItem）
    func navigateToPlayer(with item: MediaItem)
    
    /// 登出并返回登录页
    func logout()
    
    /// 归还播放器到池中
    func releasePlayer(_ player: PlayerCoreProtocol)
}

// MARK: - Coordinator 默认实现

@MainActor
extension Coordinator {
    /// 默认的导航到登录页面实现
    func navigateToLogin() {
        let loginVC = LoginViewController()
        navigationController.setViewControllers([loginVC], animated: true)
    }

    /// 默认的导航到首页实现
    func navigateToHome() {
        let homeVC = JellyfinHomeViewController()
        navigationController.pushViewController(homeVC, animated: true)
    }

    /// 默认的导航到播放器实现
    func navigateToPlayer(with url: String) {
        // 注意：此方法仅为协议默认实现，实际使用时需要提供依赖
        // 真正的实现应该使用 AppContainer 和 PlayerPool
        Logger.warning("Using default navigateToPlayer implementation without dependencies")
        let engine = PlayerEngine()
        let viewModel = PlayerViewModel(engine: engine)
        let playerVC = PlayerViewController(
            viewModel: viewModel,
            gestureManager: nil,
            urlValidator: DefaultURLValidator(),
            url: url
        )
        navigationController.pushViewController(playerVC, animated: true)
    }
}

// MARK: - NavigationActionHandler 默认实现

extension NavigationActionHandler where Self: Coordinator {
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
}
