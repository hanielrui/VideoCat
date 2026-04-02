import UIKit

/// Jellyfin 首页视图控制器
/// 显示媒体库列表
@MainActor
class JellyfinHomeViewController: BaseViewController {

    // MARK: - 属性
    private var items: [MediaItem] = []
    private let cellIdentifier = MediaItemTableViewCell.reuseIdentifier

    // MARK: - 空状态视图
    private lazy var emptyStateView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16

        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: "film")
        iconImageView.tintColor = .systemGray3
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 60),
            iconImageView.heightAnchor.constraint(equalToConstant: 60)
        ])

        let titleLabel = UILabel()
        titleLabel.text = "No Media Items"
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Your Jellyfin library is empty"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        return view
    }()

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Jellyfin"

        setupTableView()
        setupEmptyStateView()
        fetchMediaItems()
    }

    // MARK: - TableView 设置
    private func setupTableView() {
        // 注册自定义 Cell
        tableView.register(
            MediaItemTableViewCell.self,
            forCellReuseIdentifier: cellIdentifier
        )

        // 性能优化
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 108, bottom: 0, right: 0)
        tableView.backgroundColor = .systemBackground

        // 预取优化
        tableView.prefetchDataSource = self

        // 下拉刷新
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    // MARK: - 空状态视图设置
    private func setupEmptyStateView() {
        view.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            emptyStateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - 更新空状态
    private func updateEmptyState() {
        let isEmpty = items.isEmpty
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    // MARK: - 未登录提示
    private func showNotLoggedInAlert() {
        let actions = [
            UIAlertAction(title: "Login", style: .default) { [weak self] _ in
                self?.coordinator?.pop()
            },
            UIAlertAction(title: "Cancel", style: .cancel)
        ]
        coordinator?.presentAlert(title: "Not Logged In", message: "Please login to your Jellyfin server first.", actions: actions)
    }

    // MARK: - 数据加载

    /// 获取媒体列表数据
    private func fetchMediaItems() {
        // 使用容器获取 JellyfinAPI
        let container = AppContainer.shared
        
        // 检查登录状态
        guard container.jellyfinAPI.isLoggedIn else {
            showNotLoggedInAlert()
            return
        }

        guard startRequest() else { return }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let fetchedItems = try await container.jellyfinAPI.fetchItems()

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.endRequest()
                    self.items = fetchedItems
                    self.tableView.reloadData()
                    self.updateEmptyState()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.endRequest()
                    self.showError(error) { [weak self] in
                        self?.fetchMediaItems()
                    }
                }
            }
        }
    }

    /// 下拉刷新数据
    @objc private func refreshData() {
        // 使用容器获取 JellyfinAPI
        let container = AppContainer.shared
        
        guard startRequest() else {
            tableView.refreshControl?.endRefreshing()
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let fetchedItems = try await container.jellyfinAPI.fetchItems()

                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.endRequest()
                    self.tableView.refreshControl?.endRefreshing()
                    self.items = fetchedItems
                    self.tableView.reloadData()
                    self.updateEmptyState()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.endRequest()
                    self.tableView.refreshControl?.endRefreshing()
                    self.updateEmptyState()
                    self.showError(error) { [weak self] in
                        self?.fetchMediaItems()
                    }
                }
            }
        }
    }

    // MARK: - UITableViewDataSource
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: cellIdentifier,
            for: indexPath
        ) as? MediaItemTableViewCell

        if let cell = cell {
            let item = items[indexPath.row]
            cell.configure(with: item)
            return cell
        }

        // Fallback：返回默认 cell（理论上不会走到这里）
        return UITableViewCell(style: .default, reuseIdentifier: nil)
    }

    // MARK: - UITableViewDelegate
    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = items[indexPath.row]

        // 使用容器获取 JellyfinAPI
        let container = AppContainer.shared
        guard let urlString = container.jellyfinAPI.getPlayURL(itemId: item.id) else {
            showError(JellyfinError.playbackURLFailed)
            return
        }

        // 使用协调器导航到播放器
        coordinator?.navigateToPlayer(with: urlString)
    }

    // MARK: - 生命周期
    deinit {
        Logger.debug("JellyfinHomeViewController deinitialized: \(String(describing: self))")
    }
}

// MARK: - UITableViewDataSourcePrefetching
extension JellyfinHomeViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        // 预取数据优化（可扩展为图片预加载）
        Logger.debug("Prefetching rows: \(indexPaths.count)")
    }

    func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        // 取消预取
    }
}
