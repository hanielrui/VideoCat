import Foundation
import AVFoundation
import Combine

// MARK: - PlayerViewModel
/// 播放器视图模型，负责状态管理和业务逻辑
/// 使用 @MainActor 保证 UI 绑定在主线程执行
/// 采用单一数据源模式，统一管理所有播放状态
@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: - 单一状态源（统一状态）
    @Published private(set) var state: PlayerStateStruct = .idle

    // MARK: - 便捷属性（从统一状态派生，保持向后兼容）
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isBuffering: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var progress: Double = 0 // 0.0 - 1.0
    @Published private(set) var error: PlayerError?

    // MARK: - 依赖
    private let engine: PlayerEngineProtocol

    // MARK: - 订阅管理
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化
    @MainActor
    init(engine: PlayerEngineProtocol) {
        self.engine = engine
        bindEngine()
    }

    // MARK: - 绑定引擎状态（使用统一状态源）
    private func bindEngine() {
        // 订阅统一状态流
        engine.unifiedStatePublisher
            .sink { [weak self] unifiedState in
                self?.updateFromUnifiedState(unifiedState)
            }
            .store(in: &cancellables)
    }

    // MARK: - 从统一状态更新 ViewModel 属性
    private func updateFromUnifiedState(_ unifiedState: PlayerStateStruct) {
        // 更新统一状态
        self.state = unifiedState

        // 同步更新便捷属性
        self.isPlaying = unifiedState.isPlaying
        self.isBuffering = unifiedState.isBuffering
        self.currentTime = unifiedState.currentTime
        self.duration = unifiedState.duration
        self.progress = unifiedState.progress
        self.error = unifiedState.error
    }

    // MARK: - 公开接口

    /// 播放器实例
    var player: AVPlayer {
        engine.player
    }

    /// 播放媒体
    func play(url: URL) {
        error = nil
        engine.play(url: url)
    }

    /// 暂停
    func pause() {
        engine.pause()
    }

    /// 恢复播放
    func resume() {
        engine.resume()
    }

    /// 播放/暂停切换
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// 停止播放
    func stop() {
        engine.stop()
    }

    /// 跳转播放
    func seek(to seconds: Double) {
        engine.seek(to: seconds)
    }

    /// 跳转播放进度
    func seek(toProgress progress: Double) {
        let seconds = duration * progress
        engine.seek(to: seconds)
    }

    /// 立即跳转
    func seekImmediate(to seconds: Double) {
        engine.seekImmediate(to: seconds)
    }

    /// 清理资源
    func cleanup() {
        engine.cleanup()
    }

    /// 附加播放器层
    func attachPlayerLayer(_ layer: AVPlayerLayer) {
        if let engineWithLayer = engine as? PlayerEngine {
            engineWithLayer.attachPlayerLayer(layer)
        }
    }

    /// 分离播放器层
    func detachPlayerLayer() {
        if let engineWithLayer = engine as? PlayerEngine {
            engineWithLayer.detachPlayerLayer()
        }
    }

    /// 网络状态变化处理
    func handleNetworkChange(isConnected: Bool) {
        if !isConnected && isPlaying {
            pause()
            Logger.info("Network disconnected, paused playback")
        }
    }

    // MARK: - 格式化
    var currentTimeFormatted: String {
        currentTime.timeFormatted()
    }

    var durationFormatted: String {
        duration.timeFormatted()
    }

    var remainingTimeFormatted: String {
        (duration - currentTime).timeFormatted()
    }
}

// MARK: - 便捷扩展
extension PlayerViewModel {

    /// 是否可以播放
    var canPlay: Bool {
        state.canPlay
    }

    /// 是否已结束
    var isEnded: Bool {
        state.status == .ended
    }

    /// 是否有错误
    var hasError: Bool {
        state.hasError
    }

    /// 重置错误
    func clearError() {
        error = nil
    }

    /// 获取播放状态枚举（保持向后兼容）
    var status: PlayerState {
        switch state.status {
        case .idle: return .idle
        case .loading: return .loading
        case .playing: return .playing
        case .paused: return .paused
        case .buffering: return .buffering
        case .ended: return .ended
        case .error: return .error(error ?? .unknown)
        }
    }
}
