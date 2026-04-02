import UIKit
import AVFoundation
import Combine

/// 播放器视图控制器
/// 管理视频播放和用户交互
@MainActor
class PlayerViewController: UIViewController {

    // MARK: - UI 组件
    private let playerView = PlayerView()
    private let controls = PlayerControlsView()
    private let loadingView = LoadingView()

    // MARK: - 依赖（可注入）
    private let viewModel: PlayerViewModel
    private var gesture: GestureManagerProtocol?
    private let urlValidator: URLValidatorProtocol
    weak var player: Player?

    // MARK: - 属性
    private var url: String = "" {
        didSet {
            loadMedia()
        }
    }

    // 控制栏自动隐藏
    private var isControlsVisible = true
    private var controlsAutoHideTimer: Timer?

    // 订阅管理
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化方法

    // 默认初始化（保持向后兼容）
    convenience init(url: String = "") {
        self.init(
            viewModel: PlayerViewModel(),
            gestureManager: nil,
            urlValidator: DefaultURLValidator(),
            url: url
        )
    }

    // 构造函数注入（便于单元测试）
    init(
        viewModel: PlayerViewModel = PlayerViewModel(),
        gestureManager: GestureManagerProtocol? = nil,
        urlValidator: URLValidatorProtocol = DefaultURLValidator(),
        url: String = ""
    ) {
        self.viewModel = viewModel
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
        setupBindings()
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

    // MARK: - 绑定 ViewModel
    private func setupBindings() {
        // 设置播放器层
        viewModel.attachPlayerLayer(playerView.playerLayer!)

        // 绑定播放/暂停按钮
        controls.onPlayPause = { [weak self] in
            self?.viewModel.togglePlayPause()
            self?.restartControlsAutoHideTimer()
        }

        // 绑定进度拖拽
        controls.onSeek = { [weak self] value in
            guard let self = self else { return }
            self.viewModel.seek(toProgress: Double(value))
        }

        controls.onSeekBegan = { [weak self] in
            self?.hideControls()
        }

        controls.onSeekEnded = { [weak self] in
            self?.showControls()
            self?.restartControlsAutoHideTimer()
        }

        // 绑定进度更新（UIViewController 是 @MainActor）
        viewModel.$progress
            .combineLatest(viewModel.$duration)
            .sink { [weak self] progress, duration in
                self?.controls.update(current: duration * progress, total: duration)
            }
            .store(in: &cancellables)

        // 绑定缓冲状态
        viewModel.$isBuffering
            .sink { [weak self] isBuffering in
                if isBuffering {
                    self?.showLoading()
                } else {
                    self?.hideLoading()
                }
            }
            .store(in: &cancellables)

        // 绑定播放状态（使用统一状态源）
        viewModel.$state
            .sink { [weak self] state in
                switch state.status {
                case .ended:
                    self?.showControls()
                    self?.controls.update(current: 0, total: self?.viewModel.duration ?? 0)
                case .playing, .paused, .buffering:
                    self?.hideLoading()
                case .error(let error):
                    self?.showError(error.localizedDescription)
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // 绑定错误
        viewModel.$error
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.hideLoading()
                self?.showError(error.localizedDescription)
            }
            .store(in: &cancellables)

        // 手势管理
        setupGestureManager()

        // 显示加载状态
        showLoading()
    }

    private func setupGestureManager() {
        guard gesture == nil else { return }
        gesture = GestureManager(view: view, player: viewModel.player)
    }

    // MARK: - 控制栏自动隐藏
    private func setupControlsAutoHide() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        view.addGestureRecognizer(tap)

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
                  self.viewModel.isPlaying else { return }
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

        // 使用 AppContainer 获取 NetworkMonitor
        AppContainer.shared.networkMonitor.onStatusChange = { [weak self] isConnected in
            self?.handleNetworkChange(isConnected: isConnected)
        }
    }

    // MARK: - 网络状态变化
    private func handleNetworkChange(isConnected: Bool) {
        if !isConnected {
            showError("网络连接已断开")
        } else {
            hideLoading()
        }
    }

    @objc private func appDidEnterBackground() {
        viewModel.pause()
        Logger.Player.pause()
    }

    @objc private func appWillEnterForeground() {
        // 可选：自动继续播放
    }

    // MARK: - 横竖屏切换
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.playerView.setNeedsLayout()
            self.playerView.layoutIfNeeded()
        }, completion: { _ in
            self.playerView.frame = self.view.bounds
            self.controls.frame = self.view.bounds
        })
    }

    // MARK: - 媒体加载
    private func loadMedia() {
        guard urlValidator.validate(url) else {
            showError("Invalid playback URL. Please check the video source.")
            Logger.Player.playbackError(NetworkError.invalidURL)
            return
        }

        guard let mediaURL = URL(string: url) else {
            showError("Failed to parse URL.")
            Logger.Player.playbackError(NetworkError.invalidURL)
            return
        }

        // HLS 校验
        let path = mediaURL.path.lowercased()
        let isHLS = path.hasSuffix(".m3u8") ||
                    path.contains("/hls/") ||
                    path.contains("/live/") ||
                    path.contains("/stream/")

        if !isHLS {
            Logger.warning("URL does not appear to be HLS stream: \(url)")
        }

        showLoading()
        viewModel.play(url: mediaURL)
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

        viewModel.stop()
        viewModel.cleanup()
        Logger.Player.stop()
    }

    // MARK: - 错误提示
    private func showError(_ message: String) {
        hideLoading()

        let actions = [
            UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.coordinator?.pop()
            }
        ]
        coordinator?.presentAlert(title: "Error", message: message, actions: actions)
    }

    // MARK: - 清理
    deinit {
        controlsAutoHideTimer?.invalidate()
        stopPlayback()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        // 归还播放器到池中
        if let player = player {
            Task { [weak coordinator] in
                await coordinator?.releasePlayer(player)
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension PlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if let view = touch.view, view == controls || view.isDescendant(of: controls) {
            return false
        }
        return true
    }
}
