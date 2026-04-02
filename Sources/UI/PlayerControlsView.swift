import UIKit

class PlayerControlsView: UIView {

    let playButton = UIButton(type: .system)
    let slider = UISlider()
    let currentLabel = UILabel()
    let totalLabel = UILabel()
    let remainingLabel = UILabel()

    var onPlayPause: (() -> Void)?
    var onSeek: ((Float) -> Void)?
    var onSeekBegan: (() -> Void)?
    var onSeekEnded: (() -> Void)?

    // 进度条防抖
    private var isSeeking = false
    private var pendingProgress: Float = 0
    private var seekWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.4)

        playButton.setTitle("⏯", for: .normal)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        // 进度条事件
        slider.addTarget(self, action: #selector(sliderTouchBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        currentLabel.textColor = .white
        totalLabel.textColor = .white
        remainingLabel.textColor = .lightGray
        currentLabel.font = .systemFont(ofSize: 12)
        totalLabel.font = .systemFont(ofSize: 12)
        remainingLabel.font = .systemFont(ofSize: 12)

        let leftStack = UIStackView(arrangedSubviews: [playButton, currentLabel])
        leftStack.spacing = 8

        let rightStack = UIStackView(arrangedSubviews: [remainingLabel, totalLabel])
        rightStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [leftStack, slider, rightStack])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    @objc private func playTapped() {
        onPlayPause?()
    }

    @objc private func sliderTouchBegan() {
        isSeeking = true
        onSeekBegan?()
    }

    @objc private func sliderChanged() {
        pendingProgress = slider.value
        onSeek?(slider.value)
    }

    @objc private func sliderTouchEnded() {
        isSeeking = false
        onSeekEnded?()
    }

    func update(current: Double, total: Double) {
        currentLabel.text = current.timeFormatted(fallback: "--:--")
        totalLabel.text = total.timeFormatted(fallback: "--:--")

        // 剩余时间
        let remaining = max(0, total - current)
        remainingLabel.text = "-\(remaining.timeFormatted(fallback: "--:--"))"

        // 防抖：只在非拖拽时更新滑块
        if !isSeeking && total > 0 && total.isFinite {
            let progress = Float(current / total)
            if abs(progress - slider.value) > 0.001 {
                slider.value = progress
            }
        }
    }
}
