import UIKit
import Network

/// 登录视图控制器
/// 处理用户认证
@MainActor
class LoginViewController: BaseViewController {

    // MARK: - UI 组件
    let serverField = UITextField()
    let userField = UITextField()
    let passField = UITextField()
    let button = UIButton(type: .system)

    // MARK: - 防重复请求
    private var isLoggingIn = false

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "登录"

        setupUI()
    }

    // MARK: - UI 设置
    private func setupUI() {
        serverField.placeholder = "服务器地址 (如: jellyfin.example.com)"
        serverField.borderStyle = .roundedRect
        serverField.autocapitalizationType = .none
        serverField.autocorrectionType = .no
        serverField.keyboardType = .URL
        serverField.returnKeyType = .next
        serverField.clearButtonMode = .whileEditing

        userField.placeholder = "用户名"
        userField.borderStyle = .roundedRect
        userField.autocapitalizationType = .none
        userField.autocorrectionType = .no
        userField.returnKeyType = .next
        userField.clearButtonMode = .whileEditing

        passField.placeholder = "密码"
        passField.isSecureTextEntry = true
        passField.borderStyle = .roundedRect
        passField.returnKeyType = .done
        passField.clearButtonMode = .whileEditing

        // 设置代理
        serverField.delegate = self
        userField.delegate = self
        passField.delegate = self

        button.setTitle("登录", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.addTarget(self, action: #selector(login), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [serverField, userField, passField, button])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 设置按钮高度
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])

        // 点击空白处收起键盘
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - URL 标准化（复用 URLBuilder.normalize）
    private func standardizeURL(_ url: String) -> String {
        return URLBuilder.normalize(url)
    }

    // MARK: - 输入验证
    private func validateInput() -> Bool {
        guard let server = serverField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !server.isEmpty else {
            showInputError("请输入服务器地址")
            return false
        }

        // 允许 localhost
        if server == "localhost" || server.hasPrefix("localhost:") {
            return validateCredentials()
        }

        // 验证服务器 URL 格式（域名）
        let serverPattern = "^[a-zA-Z0-9][a-zA-Z0-9.-]*(\\.[a-zA-Z]{2,})(:[0-9]+)?$"
        let serverRegex = try? NSRegularExpression(pattern: serverPattern, options: [])
        let serverRange = NSRange(server.startIndex..., in: server)

        if serverRegex?.firstMatch(in: server, options: [], range: serverRange) == nil {
            // 允许 IP 地址
            let ipPattern = "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(:[0-9]+)?$"
            let ipRegex = try? NSRegularExpression(pattern: ipPattern, options: [])
            if ipRegex?.firstMatch(in: server, options: [], range: serverRange) == nil {
                showInputError("服务器地址格式无效")
                return false
            }
        }

        return validateCredentials()
    }

    // MARK: - 验证凭据
    private func validateCredentials() -> Bool {
        guard let username = userField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            showInputError("请输入用户名")
            return false
        }

        guard let password = passField.text, !password.isEmpty else {
            showInputError("请输入密码")
            return false
        }

        return true
    }

    // MARK: - 输入错误提示
    private func showInputError(_ message: String) {
        // 使用 ErrorHandling 统一处理错误
        let displayInfo = ErrorHandling.handle(
            LoginValidationError.invalidInput(message),
            context: .init(source: "LoginViewController", operation: "validateInput")
        )
        showError(message, recoverySuggestion: nil, actions: [])
    }

    // MARK: - 登录操作
    @objc private func login() {
        // 防重复点击
        guard !isLoggingIn else { return }
        guard validateInput() else { return }
        guard startRequest() else { return }

        isLoggingIn = true

        // 安全解包输入字段
        guard let serverText = serverField.text,
              let usernameText = userField.text,
              let passwordText = passField.text else {
            isLoggingIn = false
            endRequest()
            return
        }

        // 标准化 URL
        let server = standardizeURL(serverText)
        let username = usernameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordText

        Task { [weak self] in
            guard let self = self else { return }

            // 使用容器获取依赖
            let container = AppContainer.shared

            // 检查网络状态
            guard container.networkMonitor.isConnected else {
                await MainActor.run {
                    self.isLoggingIn = false
                    self.endRequest()
                    self.showInputError("网络不可用，请检查网络连接")
                }
                return
            }

            do {
                // 先设置 baseURL，再登录
                container.networkManager.baseURL = server
                try await container.jellyfinAPI.login(username: username, password: password)

                await MainActor.run {
                    self.isLoggingIn = false
                    self.endRequest()
                    // 使用协调器导航到首页
                    self.coordinator?.navigateToHome()
                }

            } catch {
                await MainActor.run {
                    self.isLoggingIn = false
                    self.endRequest()
                    self.showError(error)
                }
            }
        }
    }
}

// MARK: - UITextFieldDelegate
extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == serverField {
            userField.becomeFirstResponder()
        } else if textField == userField {
            passField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            login()
        }
        return true
    }

    // MARK: - 生命周期
    deinit {
        Logger.debug("LoginViewController deinitialized: \(String(describing: self))")
    }
}
