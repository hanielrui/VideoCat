import UIKit

class BaseViewController: UIViewController {

    // MARK: - 公共属性
    let loadingIndicator = UIActivityIndicatorView(style: .medium)
    let tableView = UITableView(frame: .zero, style: .plain)

    private var isLoading = false

    // 防止重复请求
    private(set) var isRequesting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupLoadingIndicator()
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

    private func setupLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = .gray
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - 加载状态管理
    func setLoading(_ loading: Bool) {
        guard isLoading != loading else { return }
        isLoading = loading

        if loading {
            loadingIndicator.startAnimating()
            view.isUserInteractionEnabled = false
        } else {
            loadingIndicator.stopAnimating()
            view.isUserInteractionEnabled = true
        }
    }

    // MARK: - 请求锁
    func startRequest() -> Bool {
        guard !isRequesting else { return false }
        isRequesting = true
        setLoading(true)
        return true
    }

    func endRequest() {
        isRequesting = false
        setLoading(false)
    }

    // MARK: - 用户友好的错误提示
    func showError(_ error: Error, retryAction: (() -> Void)? = nil) {
        let title = "Error"
        var message = friendlyErrorMessage(error)

        // 添加恢复建议
        if let jellyfinError = error as? JellyfinError, let suggestion = jellyfinError.recoverySuggestion {
            message += "\n\nSuggestion:\n\(suggestion)"
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        // 添加重试按钮
        if let retry = retryAction {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                retry()
            })
        }

        // 判断是否为需要返回的错误类型
        let shouldPop = shouldPopOnError(error)

        // 添加取消/返回按钮
        let cancelTitle = (retryAction != nil && shouldPop) ? "Cancel" : (shouldPop ? "Back" : "OK")
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { [weak self] _ in
            if shouldPop && retryAction == nil {
                self?.navigationController?.popViewController(animated: true)
            }
        })

        // 对于认证错误，添加重新登录按钮
        if shouldShowReLogin(error) {
            alert.addAction(UIAlertAction(title: "Re-login", style: .default) { [weak self] _ in
                self?.navigateToLogin()
            })
        }

        present(alert, animated: true)
    }

    // 判断是否需要返回
    private func shouldPopOnError(_ error: Error) -> Bool {
        if let jellyfinError = error as? JellyfinError {
            switch jellyfinError {
            case .notLoggedIn, .invalidCredentials, .serverUnreachable:
                return true
            default:
                return false
            }
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .httpError(let code) where code == 401:
                return true
            case .noNetwork, .timeout:
                return true
            default:
                return false
            }
        }

        return false
    }

    // 判断是否显示重新登录按钮
    private func shouldShowReLogin(_ error: Error) -> Bool {
        if let jellyfinError = error as? JellyfinError {
            switch jellyfinError {
            case .invalidCredentials, .notLoggedIn:
                return true
            default:
                return false
            }
        }

        if let networkError = error as? NetworkError {
            if case .httpError(let code) = networkError, code == 401 {
                return true
            }
        }

        return false
    }

    // 导航到登录页
    private func navigateToLogin() {
        JellyfinAPI.shared.logout()

        // 返回到根视图控制器
        if let navigationController = navigationController {
            navigationController.popToRootViewController(animated: true)
        }
    }

    // 将技术错误转换为用户友好的消息
    private func friendlyErrorMessage(_ error: Error) -> String {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .noNetwork:
                return "No internet connection. Please check your network settings."
            case .timeout:
                return "Request timed out. Please try again."
            case .emptyURL, .invalidURL:
                return "Invalid server address."
            case .httpError(let code):
                switch code {
                case 401:
                    return "Authentication failed. Please check your credentials."
                case 403:
                    return "Access denied. You don't have permission."
                case 404:
                    return "Server not found. Please check the server address."
                case 500...599:
                    return "Server error. Please try again later."
                default:
                    return "Request failed (Error \(code)). Please try again."
                }
            case .decodingError:
                return "Invalid server response."
            case .unknown:
                return "An error occurred. Please try again."
            }
        }

        if let jellyfinError = error as? JellyfinError {
            return jellyfinError.errorDescription ?? "An error occurred."
        }

        return "An error occurred. Please try again."
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
