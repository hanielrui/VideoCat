import UIKit
import AVFoundation

class PlayerViewController: UIViewController {

    // MARK: - UI 组件
    private let playerView = PlayerView()
    private let controls = PlayerControlsView()
    private let loadingView = LoadingView()

    // MARK: - 依赖（可注入）
    private let playerCore: PlayerCoreProtocol
    private var gesture: GestureManagerProtocol?
    private let urlValidator: URLValidatorProtocol

    // MARK: - 属性
    private var url: String = "" {
        didSet {
            loadMedia()
        }
    }

    // 控制栏自动隐藏
    private var isControlsVisible = true
    private var controlsAutoHideTimer: Timer?

    // MARK: - 初始化方法

    // 默认初始化（保持向后兼容）
    convenience init(url: String = "") {
        self.init(
            playerCore: PlayerCore(),
            gestureManager: nil,
            urlValidator: DefaultURLValidator(),
            url: url
        )
    }

    // 构造函数注入（便于单元测试）
    init(
        playerCore: PlayerCoreProtocol = PlayerCore(),
        gestureManager: GestureManagerProtocol? = nil,
        urlValidator: URLValidatorProtocol = DefaultURLValidator(),
        url: String = ""
    ) {
        self.playerCore = playerCore
        self.gesture = gestureManager
        self.urlValidator = urlValidator
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        setupUI()
        setupPlayer()
        setupNotifications()
        setupControlsAutoHide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerView.frame = view.bounds
        controls.frame = view.bounds
        loadingView.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent {
            stopPlayback()
        }
    }

    override var prefersStatusBarHidden: Bool {
        return !isControlsVisible
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return !isControlsVisible
    }

    // MARK: - UI 设置
    private func setupUI() {
        view.addSubview(playerView)
        view.addSubview(controls)
        view.addSubview(loadingView)

        loadingView.isHidden = true
    }

    // MARK: - 播放器设置
    private func setupPlayer() {
        // 设置播放器层
        if let core = playerCore as? PlayerCore {
            playerView.playerLayer.player = core.player
        } else {
            let mirror = Mirror(reflecting: playerCore)
            for child in mirror.children {
                if let player = child.value as? AVPlayer {
                    playerView.playerLayer.player = player
                    break
                }
            }
        }

        playerView.playerLayer.videoGravity = .resizeAspect

        // 播放结束回调
        playerCore.onPlaybackEnded = { [weak self] in
            guard let self = self else { return }
            self.showControls()
            self.controls.update(current: 0, total: self.playerCore.duration ?? 0)
        }

        // 时间观察
        playerCore.addTimeObserver { [weak self] current, total in
            self?.controls.update(current: current, total: total)
        }

        // 播放/暂停
        controls.onPlayPause = { [weak self] in
            guard let self = self else { return }
            if self.playerCore.isPlaying {
                self.playerCore.pause()
            } else {
                self.playerCore.resume()
            }
            self.restartControlsAutoHideTimer()
        }

        // 进度拖拽（带防抖）
        controls.onSeek = { [weak self] value in
            guard let self = self,
                  let duration = self.playerCore.duration else { return }
            self.playerCore.seek(to: Double(value) * duration)
        }

        controls.onSeekBegan = { [weak self] in
            self?.hideControls()
        }

        controls.onSeekEnded = { [weak self] in
            self?.showControls()
            self?.restartControlsAutoHideTimer()
        }

        // 播放状态回调
        playerCore.onReadyToPlay = { [weak self] in
            self?.hideLoading()
        }

        playerCore.onBuffering = { [weak self] isBuffering in
            if isBuffering {
                self?.showLoading()
            } else {
                self?.hideLoading()
            }
        }

        playerCore.onError = { [weak self] error in
            self?.hideLoading()
            self?.showError(error.localizedDescription)
        }

        // 播放结束
        playerCore.onPlaybackEnded = { [weak self] in
            guard let self = self else { return }
            self.showControls()
            self.controls.update(current: 0, total: self.playerCore.duration ?? 0)
        }

        // 手势管理
        setupGestureManager()

        // 显示加载状态
        showLoading()
    }

    private func setupGestureManager() {
        if gesture != nil {
            return
        }

        if let core = playerCore as? PlayerCore {
            gesture = GestureManager(view: view, player: core.player)
        }
    }

    // MARK: - 控制栏自动隐藏
    private func setupControlsAutoHide() {
        // 点击手势切换控制栏显示/隐藏
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        // 启动自动隐藏计时器
        startControlsAutoHideTimer()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        toggleControls()
    }

    private func toggleControls() {
        isControlsVisible.toggle()
        updateControlsVisibility()

        if isControlsVisible {
            restartControlsAutoHideTimer()
        }
    }

    private func showControls() {
        guard !isControlsVisible else { return }
        isControlsVisible = true
        updateControlsVisibility()
        restartControlsAutoHideTimer()
    }

    private func hideControls() {
        guard isControlsVisible else { return }
        isControlsVisible = false
        updateControlsVisibility()
    }

    private func updateControlsVisibility() {
        UIView.animate(withDuration: AppConstants.UI.animationDuration) {
            self.controls.alpha = self.isControlsVisible ? 1 : 0
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    private func startControlsAutoHideTimer() {
        controlsAutoHideTimer?.invalidate()
        controlsAutoHideTimer = Timer.scheduledTimer(
            withTimeInterval: 3.0,
            repeats: false
        ) { [weak self] _ in
            guard let self = self,
                  self.playerCore.isPlaying else { return }
            self.hideControls()
        }
    }

    private func restartControlsAutoHideTimer() {
        showControls()
        startControlsAutoHideTimer()
    }

    // MARK: - 通知
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        playerCore.pause()
        Logger.Player.pause()
    }

    @objc private func appWillEnterForeground() {
        // 可选：自动继续播放
    }

    // MARK: - 媒体加载
    private func loadMedia() {
        guard urlValidator.validate(url) else {
            showError("Invalid playback URL. Please check the video source.")
            Logger.Player.error(NetworkError.invalidURL)
            return
        }

        guard let mediaURL = URL(string: url) else {
            showError("Failed to parse URL.")
            Logger.Player.error(NetworkError.invalidURL)
            return
        }

        // 严格的 HLS/m3u8 校验
        let path = mediaURL.path.lowercased()
        let isHLS = path.hasSuffix(".m3u8") ||
                    path.contains("/hls/") ||
                    path.contains("/live/") ||
                    path.contains("/stream/")

        if !isHLS {
            Logger.warning("URL does not appear to be HLS stream: \(url)")
            // 允许播放，但不记录为 HLS
        }

        showLoading()
        playerCore.play(url: mediaURL)
        Logger.Player.play(url: url)
    }

    // MARK: - 加载状态
    private func showLoading() {
        loadingView.isHidden = false
        loadingView.show(message: "Loading...")
    }

    private func hideLoading() {
        loadingView.hide()
    }

    // MARK: - 播放控制
    private func stopPlayback() {
        controlsAutoHideTimer?.invalidate()
        controlsAutoHideTimer = nil

        playerCore.stop()
        playerCore.cleanup()
        Logger.Player.stop()
    }

    // MARK: - 错误提示
    private func showError(_ message: String) {
        hideLoading()

        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - 清理
    deinit {
        stopPlayback()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UIGestureRecognizerDelegate
extension PlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // 让点击事件穿透到下层视图（如 controls）
        // 如果点击的是控制栏，不切换显示状态
        if let view = touch.view, view == controls || view.isDescendant(of: controls) {
            return false
        }
        return true
    }
}
