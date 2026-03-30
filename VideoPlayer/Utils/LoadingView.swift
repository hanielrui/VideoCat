import UIKit

class LoadingView: UIView {

    private let indicator = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)

        // 设置指示器
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false

        // 设置标签
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textAlignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(indicator)
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),

            messageLabel.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    func show(message: String = "Loading...") {
        messageLabel.text = message
        isHidden = false
        indicator.startAnimating()
    }

    func hide() {
        isHidden = true
        indicator.stopAnimating()
    }

    var message: String {
        get { messageLabel.text ?? "" }
        set { messageLabel.text = newValue }
    }
}

// MARK: - BaseViewController 扩展
extension BaseViewController {

    private static var loadingViewKey: UInt8 = 0

    private var loadingView: LoadingView? {
        get {
            return objc_getAssociatedObject(self, &BaseViewController.loadingViewKey) as? LoadingView
        }
        set {
            objc_setAssociatedObject(self, &BaseViewController.loadingViewKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func showLoading(message: String = "Loading...") {
        if loadingView == nil {
            let view = LoadingView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = true
            view.alpha = 0
            self.view.addSubview(view)

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: self.view.topAnchor),
                view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
            ])

            loadingView = view
        }

        loadingView?.show(message: message)

        UIView.animate(withDuration: 0.2) {
            self.loadingView?.alpha = 1
        }
    }

    func hideLoading() {
        UIView.animate(withDuration: 0.2) {
            self.loadingView?.alpha = 0
        } completion: { _ in
            self.loadingView?.hide()
        }
    }

    // 更新加载状态
    func updateLoadingState(_ loading: Bool) {
        if loading {
            showLoading()
        } else {
            hideLoading()
        }
    }
}
