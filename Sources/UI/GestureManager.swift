import UIKit
import AVFoundation
import MediaPlayer

/// 手势管理器
@MainActor
class GestureManager: NSObject, GestureManagerProtocol {

    private weak var view: UIView?
    private weak var player: AVPlayer?

    private var startPoint: CGPoint = .zero
    private var isHorizontal: Bool?

    private var initialBrightness: CGFloat = 0
    private var initialVolume: Float = 0

    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?

    private var panGesture: UIPanGestureRecognizer?

    private let directionThreshold: CGFloat = 10

    // 反馈视图容器
    private weak var feedbackView: UIView?

    required init(view: UIView, player: AVPlayer) {
        self.view = view
        self.player = player
        super.init()

        setupVolume()
        addGesture()
    }

    private func setupVolume() {
        volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView?.showsVolumeSlider = false
        volumeView?.isUserInteractionEnabled = false

        if let volumeView = volumeView {
            // iOS 13+ 使用 connectedScenes
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first(where: { $0.isKeyWindow }) {
                window.addSubview(volumeView)
            }

            for v in volumeView.subviews {
                if let s = v as? UISlider {
                    volumeSlider = s
                    break
                }
            }
        }
    }

    private func addGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        view?.addGestureRecognizer(pan)
        panGesture = pan
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            initialVolume = AVAudioSession.sharedInstance().outputVolume
        } catch {
            initialVolume = volumeSlider?.value ?? 0.5
        }
    }

    @MainActor
    @objc private func pan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            startPoint = pan.location(in: view)
            initialBrightness = UIScreen.main.brightness

            // 确保 AVAudioSession 操作在主线程执行
            setupAudioSession()

            isHorizontal = nil

        case .changed:
            let currentPoint = pan.location(in: view)
            let deltaX = currentPoint.x - startPoint.x
            let deltaY = currentPoint.y - startPoint.y

            if isHorizontal == nil {
                let absX = abs(deltaX)
                let absY = abs(deltaY)

                if absX > directionThreshold || absY > directionThreshold {
                    isHorizontal = absX > absY
                } else {
                    return
                }
            }

            guard let isHorizontal = isHorizontal else { return }

            if isHorizontal {
                seek(deltaX)
            } else {
                if startPoint.x < (view?.bounds.width ?? 0) / 2 {
                    brightness(deltaY)
                } else {
                    volume(deltaY)
                }
            }

            pan.setTranslation(.zero, in: view)

        case .ended, .cancelled:
            isHorizontal = nil

        default:
            break
        }
    }

    @MainActor
    private func seek(_ dx: CGFloat) {
        guard let player = player,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite && duration > 0 else { return }

        let current = player.currentTime().seconds
        let delta = Double(dx / 200) * duration * 0.1
        let target = max(0, min(duration, current + delta))

        player.seek(to: CMTime(seconds: target, preferredTimescale: 1))

        // 显示快进/快退反馈
        _ = Int(delta)
        showFeedback(type: .seek, value: CGFloat(delta), currentValue: target, totalValue: duration)
    }

    @MainActor
    private func brightness(_ dy: CGFloat) {
        let delta = -dy / 300
        let newBrightness = max(0, min(1, initialBrightness + delta))
        UIScreen.main.brightness = newBrightness

        // 显示亮度反馈
        showFeedback(type: .brightness, value: newBrightness)
    }

    @MainActor
    private func volume(_ dy: CGFloat) {
        let delta = Float(-dy / 300)
        let newVolume = max(0, min(1, initialVolume + delta))

        if let slider = volumeSlider {
            slider.value = newVolume
        }
        // 无论 slider 是否存在，都需要设置实际音量
        setVolume(newVolume)

        // 显示音量反馈
        showFeedback(type: .volume, value: CGFloat(newVolume))
    }

    @MainActor
    private func setVolume(_ volume: Float) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
        } catch {
            Logger.warning("Failed to set volume: \(error.localizedDescription)")
        }
    }

    // MARK: - 视觉反馈
    private enum FeedbackType {
        case brightness
        case volume
        case seek

        var icon: String {
            switch self {
            case .brightness: return "sun.max.fill"
            case .volume: return "speaker.wave.2.fill"
            case .seek: return "arrow.right"
            }
        }
    }

    @MainActor
    private func showFeedback(type: FeedbackType, value: CGFloat, currentValue: Double? = nil, totalValue: Double? = nil) {
        guard let view = view else { return }

        // 移除旧的反馈视图
        feedbackView?.removeFromSuperview()

        // 创建反馈视图
        let feedback = UIView()
        feedback.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        feedback.layer.cornerRadius = 12
        feedback.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // 图标 (使用 SF Symbols)
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: type.icon)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // 文本
        let textLabel = UILabel()
        textLabel.textColor = .white
        textLabel.font = .systemFont(ofSize: 14, weight: .medium)

        switch type {
        case .brightness:
            let percentage = Int(value * 100)
            textLabel.text = "\(percentage)%"

        case .volume:
            let percentage = Int(value * 100)
            textLabel.text = "\(percentage)%"

        case .seek:
            if let current = currentValue, let total = totalValue {
                textLabel.text = "\(current.shortTimeFormatted()) / \(total.shortTimeFormatted())"
            }
        }

        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(textLabel)

        // 设置图标大小
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32)
        ])

        feedback.addSubview(stackView)
        view.addSubview(feedback)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: feedback.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: feedback.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: feedback.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: feedback.trailingAnchor, constant: -16),

            feedback.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            feedback.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            feedback.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.6),
            feedback.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])

        feedbackView = feedback

        // 动画
        feedback.alpha = 0
        feedback.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        UIView.animate(withDuration: 0.2) {
            feedback.alpha = 1
            feedback.transform = .identity
        } completion: { _ in
            // 自动隐藏
            UIView.animate(withDuration: 0.3, delay: 1.0) {
                feedback.alpha = 0
            } completion: { _ in
                feedback.removeFromSuperview()
            }
        }
    }

    // MARK: - 清理
    @MainActor
    private func cleanup() {
        if let gesture = panGesture, let view = view {
            view.removeGestureRecognizer(gesture)
            panGesture = nil
        }

        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeSlider = nil
    }

    deinit {
        Task { @MainActor in
            self.cleanup()
        }
        Logger.debug("GestureManager deinitialized")
    }
}

// MARK: - UIGestureRecognizerDelegate
extension GestureManager: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}
