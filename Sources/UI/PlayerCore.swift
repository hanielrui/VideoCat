import AVFoundation
import Combine

/// 播放器核心类 - 保留向后兼容的封装层
/// 内部使用 PlayerEngine 处理播放逻辑
/// 提供回调接口用于兼容旧代码
/// 使用 @MainActor 保证 UI 操作在主线程执行
@MainActor
class PlayerCore: PlayerCoreProtocol {

    // MARK: - 属性
    let player: AVPlayer

    // 内部引擎
    private let engine: Player

    // MARK: - 回调（保持向后兼容）
    var onPlaybackEnded: (() -> Void)?
    var onError: ((PlayerError) -> Void)?
    var onBuffering: ((Bool) -> Void)?
    var onReadyToPlay: (() -> Void)?
    var onStateChange: ((PlayerState) -> Void)?

    // MARK: - 状态（保持向后兼容）
    private(set) var state: PlayerState = .idle

    // MARK: - 初始化
    init() {
        self.engine = PlayerEngine()
        self.player = engine.player
        bindEngine()
    }

    // 可注入初始化（便于单元测试）
    init(engine: Player) {
        self.engine = engine
        self.player = engine.player
        bindEngine()
    }

    // MARK: - 绑定引擎状态
    private func bindEngine() {
        // 订阅统一状态流（PlayerEngine 是 @MainActor，发布已在主线程）
        engine.unifiedStatePublisher
            .sink { [weak self] unifiedState in
                guard let self = self else { return }
                self.updateFromUnifiedState(unifiedState)
            }
            .store(in: &cancellables)

        // 订阅错误流
        engine.errorPublisher
            .sink { [weak self] error in
                self?.onError?(error)
            }
            .store(in: &cancellables)

        // 订阅缓冲流
        engine.bufferingPublisher
            .sink { [weak self] isBuffering in
                self?.onBuffering?(isBuffering)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 从统一状态更新
    private func updateFromUnifiedState(_ unifiedState: PlayerStateStruct) {
        let newState: PlayerState
        switch unifiedState.status {
        case .idle: newState = .idle
        case .loading: newState = .loading
        case .playing: newState = .playing
        case .paused: newState = .paused
        case .buffering: newState = .buffering
        case .ended:
            newState = .ended
            onPlaybackEnded?()
        case .error:
            newState = .error(unifiedState.error ?? .unknown)
        }

        if state != newState {
            state = newState
            onStateChange?(newState)
        }
    }

    // MARK: - Player 协议实现（代理到引擎）

    var isPlaying: Bool { engine.isPlaying }
    var currentTime: Double { engine.currentTime }
    var duration: Double? { engine.duration }

    var unifiedStatePublisher: AnyPublisher<PlayerStateStruct, Never> {
        engine.unifiedStatePublisher
    }

    var progressPublisher: AnyPublisher<(Double, Double), Never> {
        engine.progressPublisher
    }

    var bufferingPublisher: AnyPublisher<Bool, Never> {
        engine.bufferingPublisher
    }

    var errorPublisher: AnyPublisher<PlayerError, Never> {
        engine.errorPublisher
    }

    func play(url: URL) { engine.play(url: url) }
    func pause() { engine.pause() }
    func resume() { engine.resume() }
    func stop() { engine.stop() }
    func seek(to seconds: Double) { engine.seek(to: seconds) }
    func seekImmediate(to seconds: Double) { engine.seekImmediate(to: seconds) }
    func cleanup() {
        engine.cleanup()
        engine.detachPlayerLayer()
        NotificationCenter.default.removeObserver(self)
    }
    func attachPlayerLayer(_ layer: AVPlayerLayer) { engine.attachPlayerLayer(layer) }
    func detachPlayerLayer() { engine.detachPlayerLayer() }

    func addTimeObserver(handler: @escaping @MainActor (Double, Double) -> Void) {
        engine.progressPublisher
            .sink { current, duration in
                Task { @MainActor in
                    handler(current, duration)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 网络状态变化
    func handleNetworkChange(isConnected: Bool) {
        if !isConnected && isPlaying {
            pause()
            Logger.info("Network disconnected, paused playback")
        }
    }

    // MARK: - 销毁
    deinit {
        // 注意：@MainActor 类的 deinit 会在释放线程执行
        // 因此只做最小化清理，避免访问 UI 资源
        cancellables.removeAll()
        // NotificationCenter 观察者在 explicitCleanup() 中清理
        Logger.debug("PlayerCore deinitialized")
    }
    
    /// 显式清理方法（推荐在 UIViewController.viewDidDisappear 中调用）
    func explicitCleanup() {
        cleanup()
        engine.detachPlayerLayer()
        NotificationCenter.default.removeObserver(self)
        Logger.debug("PlayerCore explicitly cleaned up")
    }
}
