import UIKit

class MediaItemTableViewCell: UITableViewCell {

    static let reuseIdentifier = "MediaItemTableViewCell"

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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        // 时长
        if let seconds = item.runTimeSeconds {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            durationLabel.text = String(format: " %02d:%02d ", minutes, remainingSeconds)
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

    private func loadThumbnail(item: MediaItem) {
        // 这里可以集成图片库（如 Kingfisher）
        // 当前简化处理：只显示占位图
        guard item.thumbnail != nil else { return }
        // 实际项目中可使用：
        // thumbnailView.kf.setImage(with: url, placeholder: UIImage(systemName: "film"))
    }

    // MARK: - 复用重置
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        subtitleLabel.text = nil
        thumbnailView.image = UIImage(systemName: "film")
        durationLabel.isHidden = true
    }
}
