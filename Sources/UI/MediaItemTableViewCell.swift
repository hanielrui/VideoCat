import UIKit

class MediaItemTableViewCell: UITableViewCell {

    static let reuseIdentifier = "MediaItemTableViewCell"

    // MARK: - 依赖（可注入）
    private var imageCache: ImageCacheProtocol?
    private var jellyfinAPI: JellyfinAPIClient?

    // MARK: - UI 组件
    private let thumbnailView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = AppConstants.UI.cornerRadius
        imageView.backgroundColor = .secondarySystemFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 2
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - 初始化

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        setupDependencies()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 依赖注入
    private func setupDependencies() {
        // 使用 AppContainer 获取依赖
        let container = AppContainer.shared
        self.imageCache = container.imageCache
        self.jellyfinAPI = container.jellyfinAPI

        // 设置 UIImageView 使用注入的缓存
        thumbnailView.setImageCache(container.imageCache)
    }

    /// 配置依赖（供外部调用，便于单元测试）
    func configure(imageCache: ImageCacheProtocol?, jellyfinAPI: JellyfinAPIClient?) {
        self.imageCache = imageCache
        self.jellyfinAPI = jellyfinAPI
        thumbnailView.setImageCache(imageCache)
    }

    // MARK: - UI 设置
    private func setupUI() {
        backgroundColor = .systemBackground
        accessoryType = .disclosureIndicator

        // 添加子视图
        contentView.addSubview(thumbnailView)
        contentView.addSubview(stackView)
        thumbnailView.addSubview(durationLabel)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        // 布局约束
        NSLayoutConstraint.activate([
            // 缩略图
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 80),
            thumbnailView.heightAnchor.constraint(equalToConstant: 60),

            // 标题和副标题
            stackView.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            // 时长标签
            durationLabel.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -4),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -4),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            durationLabel.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    // MARK: - 配置
    func configure(with item: MediaItem) {
        titleLabel.text = item.name

        // 副标题：类型 + 年份
        var subtitleParts: [String] = []
        if let type = item.type {
            subtitleParts.append(type)
        }
        if let year = item.productionYear {
            subtitleParts.append(String(year))
        }
        subtitleLabel.text = subtitleParts.isEmpty ? "Unknown" : subtitleParts.joined(separator: " • ")

        // 时长（使用 Formatters 统一格式化）
        if let seconds = item.runTimeSeconds {
            durationLabel.text = " \(Double(seconds).shortTimeFormatted()) "
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        // 缩略图占位
        thumbnailView.image = UIImage(systemName: "film")
        thumbnailView.tintColor = .tertiaryLabel

        // 异步加载缩略图（简化版，实际可用 Kingfisher）
        loadThumbnail(item: item)
    }

    private var currentThumbnailURL: String?
    private var imageLoadTask: Task<Void, Never>?

    // MARK: - 复用准备
    override func prepareForReuse() {
        super.prepareForReuse()
        // 取消正在进行的图片加载请求
        imageLoadTask?.cancel()
        imageLoadTask = nil
        currentThumbnailURL = nil
        // 重置所有视图
        thumbnailView.image = UIImage(systemName: "film")
        thumbnailView.tintColor = .tertiaryLabel
        titleLabel.text = nil
        subtitleLabel.text = nil
        durationLabel.isHidden = true
    }

    private func loadThumbnail(item: MediaItem) {
        guard let tag = item.thumbnail else { return }

        // 构建完整的 thumbnail URL
        guard let thumbnailURL = buildThumbnailURL(from: tag, itemId: item.id) else { return }

        currentThumbnailURL = thumbnailURL

        // 直接使用 UIImageView 的 setImage 方法（已配置缓存）
        guard let url = URL(string: thumbnailURL) else { return }
        thumbnailView.setImage(from: url, placeholder: UIImage(systemName: "film"))
    }

    private func buildThumbnailURL(from tag: String, itemId: String) -> String? {
        // 使用注入的 jellyfinAPI
        guard let api = jellyfinAPI else { return nil }

        let baseURL = api.baseURL
        // 通过协议属性获取 token
        let token = api.token

        guard !baseURL.isEmpty, !token.isEmpty else { return nil }

        // 对tag和token进行URL编码
        guard let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return "\(baseURL)/Items/\(itemId)/Images/Primary?tag=\(encodedTag)&api_key=\(encodedToken)"
    }
}
