import AVFoundation

class PlayerCore: PlayerCoreProtocol {

    let player = AVPlayer()
    private var timeObserver: Any?
    private var playerItemObserver: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var bufferingObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?

    // Seek 防抖
    private var seekWorkItem: DispatchWorkItem?
    private let seekDebounceInterval: TimeInterval = 0.3

    var onPlaybackEnded: (() -> Void)?
    var onError: ((PlayerError) -> Void)?
    var onBuffering: ((Bool) -> Void)?
    var onReadyToPlay: (() -> Void)?

    // MARK: - 播放
    func play(url: URL) {
        // 先清理之前的资源
        cleanup()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()

        // 监听播放状态和结束
        setupPlaybackEndObserver(item: item)
        setupStatusObserver(item: item)
        setupBufferingObserver(item: item)

        Logger.Player.play(url: url.absoluteString)
    }

    // MARK: - 暂停
    func pause() {
        player.pause()
        Logger.Player.pause()
    }

    // MARK: - 继续播放
    func resume() {
        player.play()
        Logger.Player.play(url: "resume")
    }

    // MARK: - 停止播放
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        cleanup()
        Logger.Player.stop()
    }

    // MARK: - 清理资源
    func cleanup() {
        // 取消 pending seek
        seekWorkItem?.cancel()
        seekWorkItem = nil

        // 移除时间观察者
        removeTimeObserver()

        // 移除播放结束通知
        removePlaybackEndObserver()

        // 取消 KVO 观察
        playerItemObserver?.invalidate()
        playerItemObserver = nil

        bufferingObserver?.invalidate()
        bufferingObserver = nil

        statusObserver?.invalidate()
        statusObserver = nil

        Logger.debug("PlayerCore cleaned up")
    }

    // MARK: - 跳转（带防抖）
    func seek(to seconds: Double) {
        guard seconds.isFinite && seconds >= 0 else {
            Logger.warning("Invalid seek time: \(seconds)")
            return
        }

        // 取消之前的 seek
        seekWorkItem?.cancel()

        // 创建新的 seek 工作项
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            Logger.debug("Seek to: \(seconds)")
        }

        seekWorkItem = workItem

        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + seekDebounceInterval, execute: workItem)
    }

    // MARK: - 立即 Seek（用于进度条拖拽结束）
    func seekImmediate(to seconds: Double) {
        seekWorkItem?.cancel()
        seekWorkItem = nil

        guard seconds.isFinite && seconds >= 0 else {
            Logger.warning("Invalid seek time: \(seconds)")
            return
        }

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - 时间观察者
    func addTimeObserver(handler: @escaping (Double, Double) -> Void) {
        removeTimeObserver()

        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self = self,
                  let duration = self.player.currentItem?.duration.seconds,
                  duration.isFinite && duration > 0 else { return }

            handler(time.seconds, duration)
        }

        Logger.debug("Time observer added")
    }

    private func removeTimeObserver() {
        guard let observer = timeObserver else { return }
        player.removeTimeObserver(observer)
        timeObserver = nil
        Logger.debug("Time observer removed")
    }

    // MARK: - 播放结束观察
    private func setupPlaybackEndObserver(item: AVPlayerItem) {
        // 先移除之前的观察者
        removePlaybackEndObserver()

        // KVO 观察播放状态
        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                // 添加播放结束通知
                self?.addPlaybackEndObserver(for: item)
                self?.onReadyToPlay?()
            } else if item.status == .failed {
                let error = item.error
                Logger.error("Playback failed: \(error?.localizedDescription ?? "Unknown")")
                self?.onError?(.playbackFailed(error))
            }
        }
    }

    // MARK: - 播放状态观察
    private func setupStatusObserver(item: AVPlayerItem) {
        statusObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                Logger.debug("Player ready to play")
            case .failed:
                let error = item.error
                Logger.error("Player status failed: \(error?.localizedDescription ?? "Unknown")")
                self?.onError?(.loadFailed(error))
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: - 缓冲状态观察
    private func setupBufferingObserver(item: AVPlayerItem) {
        bufferingObserver?.invalidate()

        bufferingObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let isBuffering = !item.isPlaybackLikelyToKeepUp
            self?.onBuffering?(isBuffering)
            Logger.debug("Buffering: \(isBuffering)")
        }
    }

    private func addPlaybackEndObserver(for item: AVPlayerItem) {
        removePlaybackEndObserver()

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onPlaybackEnded?()
            Logger.info("Playback ended")
        }
    }

    private func removePlaybackEndObserver() {
        if let observer = playbackEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndObserver = nil
        }
    }

    // MARK: - 播放状态
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

    deinit {
        cleanup()
        Logger.debug("PlayerCore deinitialized")
    }
}
