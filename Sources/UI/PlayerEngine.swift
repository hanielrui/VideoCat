import AVFoundation
import Combine

// MARK: - 播放器引擎协议

/// 纯播放逻辑层协议
/// 新代码应使用 Player 协议
protocol PlayerEngineProtocol: Player {
    // Player 协议已包含所有必要接口
}

// MARK: - 播放器引擎实现

/// 播放器引擎实现
/// 使用 NSObject 以支持 KVO 观察者
/// 所有 UI 相关操作通过 @MainActor 保证线程安全
@MainActor
final class PlayerEngine: NSObject, PlayerEngineProtocol, Player {

    // MARK: - 属性
    let player = AVPlayer()

    // 播放器层引用
    private var playerLayer: AVPlayerLayer?

    // 观察者
    private var timeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var bufferingObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    // Seek 防抖
    private var seekTask: Task<Void, Never>?
    private let seekDebounceInterval: TimeInterval = 0.3

    // Combine Publishers
    private let progressSubject = PassthroughSubject<(Double, Double), Never>()
    private let bufferingSubject = CurrentValueSubject<Bool, Never>(false)
    private let errorSubject = PassthroughSubject<PlayerError, Never>()

    // 统一状态源（单一数据源）
    // 重构后：统一使用 unifiedStateSubject 作为唯一数据源
    private let unifiedStateSubject = CurrentValueSubject<PlayerStateStruct, Never>(.idle)

    var unifiedStatePublisher: AnyPublisher<PlayerStateStruct, Never> {
        unifiedStateSubject.eraseToAnyPublisher()
    }

    var progressPublisher: AnyPublisher<(Double, Double), Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var bufferingPublisher: AnyPublisher<Bool, Never> {
        bufferingSubject.eraseToAnyPublisher()
    }

    var errorPublisher: AnyPublisher<PlayerError, Never> {
        errorSubject.eraseToAnyPublisher()
    }

    // MARK: - 公开属性
    var isPlaying: Bool {
        player.rate > 0
    }

    var currentTime: Double {
        player.currentTime().seconds
    }

    var duration: Double? {
        guard let duration = player.currentItem?.duration.seconds,
              duration.isFinite else { return nil }
        return duration
    }

    // MARK: - 更新统一状态（单一数据源）
    private func updateUnifiedState(
        status: PlayerStateStruct.PlayerStatus,
        currentTime: Double? = nil,
        duration: Double? = nil,
        bufferProgress: Double? = nil,
        error: PlayerError? = nil,
        url: URL? = nil
    ) {
        let current = currentTime ?? self.currentTime
        let total = duration ?? self.duration ?? 0
        let buffer = bufferProgress ?? 0

        var newState = PlayerStateStruct(
            status: status,
            currentTime: current,
            duration: total,
            bufferProgress: buffer,
            progress: total > 0 ? current / total : 0,
            error: error,
            url: url
        )

        // 如果有 URL，保持之前的 URL
        if let existingURL = unifiedStateSubject.value.url, url == nil {
            newState.url = existingURL
        }

        unifiedStateSubject.send(newState)
    }

    // MARK: - 初始化
    override init() {
        super.init()
        setupAudioSession()
        setupNotifications()
    }

    // MARK: - 音频会话配置
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Logger.error("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - 通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    // MARK: - 音频中断处理
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            pause()
            Logger.info("Audio interruption began, paused playback")
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                resume()
                Logger.info("Audio interruption ended, resumed playback")
            }
        @unknown default:
            break
        }
    }

    // MARK: - 音频路由变化处理
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            pause()
            Logger.info("Audio route changed, paused playback")
        default:
            break
        }
    }

    // MARK: - 播放器层管理
    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        self.playerLayer = layer
        layer.player = player
        layer.videoGravity = .resizeAspect
    }

    func detachPlayerLayer() {
        playerLayer?.player = nil
        playerLayer = nil
    }

    // MARK: - 播放控制
    func play(url: URL) {
        cleanup()

        updateUnifiedState(status: .loading, url: url)

        // 加载 asset（@MainActor 已保证主线程执行）
        let asset = AVURLAsset(url: url)

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let isPlayable = try await asset.load(.isPlayable)

                await MainActor.run {
                    guard isPlayable else {
                        let error = NSError(
                            domain: "PlayerEngine",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Asset is not playable"]
                        )
                        self.errorSubject.send(.loadFailed(error))
                        self.updateUnifiedState(status: .error, error: .loadFailed(error))
                        return
                    }

                    let item = AVPlayerItem(asset: asset)
                    item.preferredForwardBufferDuration = 3.0

                    self.player.replaceCurrentItem(with: item)
                    self.player.play()

                    self.setupObservers(for: item)
                    Logger.Player.play(url: url.absoluteString)
                }
            } catch {
                await MainActor.run {
                    self.errorSubject.send(.loadFailed(error))
                    self.updateUnifiedState(status: .error, error: .loadFailed(error))
                }
            }
        }
    }

    private func setupObservers(for item: AVPlayerItem) {
        // 播放结束观察
        setupPlaybackEndObserver(item: item)

        // 状态观察
        setupStatusObserver(item: item)

        // 缓冲观察
        setupBufferingObserver(item: item)

        // 播放速率观察
        setupRateObserver()

        // 时间观察
        setupTimeObserver()
    }

    private func setupTimeObserver() {
        removeTimeObserver()

        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  let duration = self.player.currentItem?.duration.seconds,
                  duration.isFinite && duration > 0 else { return }

            let current = time.seconds
            self.progressSubject.send((current, duration))

            // 更新统一状态
            self.updateUnifiedState(
                status: self.unifiedStateSubject.value.status == .buffering ? .buffering :
                       self.player.rate > 0 ? .playing : .paused,
                currentTime: current,
                duration: duration
            )
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func setupRateObserver() {
        rateObserver?.invalidate()
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }

            if player.rate == 0 {
                if self.unifiedStateSubject.value.status != .buffering {
                    self.updateUnifiedState(status: .paused)
                }
                Logger.debug("Playback rate became 0")
            } else {
                self.updateUnifiedState(status: .playing)
            }
        }
    }

    private func setupStatusObserver(item: AVPlayerItem) {
        statusObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                Logger.debug("Player ready to play")
            case .failed:
                let error = item.error
                Logger.error("Player status failed: \(error?.localizedDescription ?? "Unknown")")
                self?.errorSubject.send(.loadFailed(error))
                self?.updateUnifiedState(status: .error, error: .loadFailed(error))
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    private func setupBufferingObserver(item: AVPlayerItem) {
        bufferingObserver?.invalidate()

        bufferingObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }

            let isBuffering = !item.isPlaybackLikelyToKeepUp
            self.bufferingSubject.send(isBuffering)

            if isBuffering {
                self.updateUnifiedState(status: .buffering)
            } else if self.player.rate > 0 {
                self.updateUnifiedState(status: .playing)
            }

            Logger.debug("Buffering: \(isBuffering)")
        }
    }

    private func setupPlaybackEndObserver(item: AVPlayerItem) {
        removePlaybackEndObserver()

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.updateUnifiedState(status: .ended)
            Logger.info("Playback ended")
        }
    }

    private func removePlaybackEndObserver() {
        if let observer = playbackEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndObserver = nil
        }
    }

    // MARK: - 播放控制
    func pause() {
        player.pause()
        updateUnifiedState(status: .paused)
        Logger.Player.pause()
    }

    func resume() {
        player.play()
        updateUnifiedState(status: .playing)
        Logger.Player.play(url: "resume")
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        cleanup()
        updateUnifiedState(status: .idle, currentTime: 0, duration: 0)
        Logger.Player.stop()
    }

    // MARK: - Seek
    func seek(to seconds: Double) {
        guard seconds.isFinite && seconds >= 0 else {
            Logger.warning("Invalid seek time: \(seconds)")
            return
        }

        seekTask?.cancel()

        // 使用 Task 实现防抖（@MainActor 保证 player.seek 在主线程执行）
        seekTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seekDebounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                Logger.debug("Seek to: \(seconds)")
            }
        }
    }

    func seekImmediate(to seconds: Double) {
        seekTask?.cancel()
        seekTask = nil

        guard seconds.isFinite && seconds >= 0 else {
            Logger.warning("Invalid seek time: \(seconds)")
            return
        }

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - 清理
    func cleanup() {
        seekTask?.cancel()
        seekTask = nil

        removeTimeObserver()
        removePlaybackEndObserver()

        bufferingObserver?.invalidate()
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        bufferingObserver = nil
        statusObserver = nil
        rateObserver = nil

        Logger.debug("PlayerEngine cleaned up")
    }

    // MARK: - 销毁
    deinit {
        cleanup()
        detachPlayerLayer()
        NotificationCenter.default.removeObserver(self)
        Logger.debug("PlayerEngine deinitialized")
    }
}
