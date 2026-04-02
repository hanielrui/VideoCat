import UIKit

/// 基础视图控制器，提供通用功能
/// 使用 @MainActor 确保所有 UI 操作在主线程执行
@MainActor
class BaseViewController: UIViewController {

    // MARK: - 公共属性
    let tableView = UITableView(frame: .zero, style: .plain)

    /// 导航协调器
    weak var coordinator: AppCoordinatorProtocol?

    // 防止重复请求
    private(set) var isRequesting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }

    // MARK: - TableView 设置
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - 请求锁（使用 LoadingView 扩展）
    func startRequest() -> Bool {
        guard !isRequesting else { return false }
        isRequesting = true
        showLoading()
        return true
    }

    func endRequest() {
        isRequesting = false
        hideLoading()
    }

    // MARK: - 用户友好的错误提示
    func showError(_ error: Error, retryAction: (() -> Void)? = nil) {
        // 使用 ErrorHandling 辅助类处理错误
        let errorInfo = ErrorHandling.logAndHandle(error)
        var message = errorInfo.message

        // 添加恢复建议
        if let recoverySuggestion = errorInfo.recoverySuggestion {
            message += "\n\nSuggestion:\n\(recoverySuggestion)"
        }

        // 判断是否为需要返回的错误类型
        let shouldPop = shouldPopOnError(error)

        // 使用 ErrorHandling 构建标准错误处理流程
        var actions: [UIAlertAction] = []

        // 添加重试按钮
        if let retry = retryAction {
            actions.append(UIAlertAction(title: "Retry", style: .default) { _ in
                retry()
            })
        }

        // 添加取消/返回按钮
        let cancelTitle = (retryAction != nil && shouldPop) ? "Cancel" : (shouldPop ? "Back" : "OK")
        actions.append(UIAlertAction(title: cancelTitle, style: .cancel) { [weak self] _ in
            if shouldPop && retryAction == nil {
                self?.coordinator?.pop()
            }
        })

        // 对于认证错误，添加重新登录按钮
        if shouldShowReLogin(error) {
            actions.append(UIAlertAction(title: "Re-login", style: .default) { [weak self] _ in
                self?.coordinator?.logout()
            })
        }

        // 使用 Coordinator 展示 Alert
        coordinator?.presentAlert(title: "Error", message: message, actions: actions)
    }

    // MARK: - 错误判断

    /// 判断是否需要返回
    private func shouldPopOnError(_ error: Error) -> Bool {
        if let jellyfinError = error.asJellyfinError {
            switch jellyfinError {
            case .notLoggedIn, .invalidCredentials, .serverUnreachable:
                return true
            default:
                return false
            }
        }

        if let networkError = error.asNetworkError {
            switch networkError.category {
            case .auth:
                return true  // unauthorized, forbidden, tokenExpired
            case .network:
                return true  // noNetwork, timeout, etc.
            default:
                return false
            }
        }

        return false
    }

    /// 判断是否显示重新登录按钮
    private func shouldShowReLogin(_ error: Error) -> Bool {
        if let jellyfinError = error.asJellyfinError {
            switch jellyfinError {
            case .invalidCredentials, .notLoggedIn:
                return true
            default:
                return false
            }
        }

        if let networkError = error.asNetworkError {
            return networkError.category == .auth
        }

        return false
    }

    // MARK: - 生命周期
    deinit {
        Logger.debug("BaseViewController deinitialized: \(String(describing: self))")
    }
}

// MARK: - UITableViewDataSource
extension BaseViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return UITableViewCell()
    }
}

// MARK: - UITableViewDelegate
extension BaseViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}