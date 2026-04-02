import AVFoundation
import UIKit
import Combine

// MARK: - 播放状态

/// 播放器状态枚举 - 统一管理播放状态
enum PlayerState: Equatable {
    /// 空闲状态
    case idle
    /// 加载中
    case loading
    /// 播放中
    case playing
    /// 已暂停
    case paused
    /// 缓冲中
    case buffering
    /// 播放结束
    case ended
    /// 错误状态
    case error(PlayerError)

    // MARK: - Equatable 实现

    static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading, .loading):
            return true
        case (.playing, .playing):
            return true
        case (.paused, .paused):
            return true
        case (.buffering, .buffering):
            return true
        case (.ended, .ended):
            return true
        case (.error, .error):
            return true  // 忽略关联值比较
        default:
            return false
        }
    }

    // MARK: - 状态判断

    /// 是否可以播放
    var canPlay: Bool {
        switch self {
        case .playing, .paused, .ended:
            return true
        default:
            return false
        }
    }

    /// 是否正在缓冲
    var isBuffering: Bool {
        self == .buffering || self == .loading
    }

    /// 是否出错
    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}

// MARK: - 统一状态模型（单一数据源）

/// 播放器统一状态结构体
/// 解决状态分散、多源头更新导致的不同步和 UI 抖动问题
struct PlayerStateStruct: Equatable {
    /// 播放状态枚举
    var status: PlayerStatus
    /// 当前播放时间（秒）
    var currentTime: Double
    /// 媒体总时长（秒）
    var duration: Double
    /// 缓冲进度（0.0 - 1.0）
    var bufferProgress: Double
    /// 播放进度（0.0 - 1.0）
    var progress: Double
    /// 是否有错误
    var error: PlayerError?
    /// 媒体 URL
    var url: URL?

    /// 播放状态枚举
    enum PlayerStatus: Equatable {
        case idle
        case loading
        case playing
        case paused
        case buffering
        case ended
        case error
    }

    /// 默认空闲状态
    static let idle = PlayerStateStruct(
        status: .idle,
        currentTime: 0,
        duration: 0,
        bufferProgress: 0,
        progress: 0,
        error: nil,
        url: nil
    )

    /// 从 PlayerState 转换
    static func from(_ state: PlayerState, currentTime: Double = 0, duration: Double = 0, bufferProgress: Double = 0) -> PlayerStateStruct {
        let status: PlayerStatus
        switch state {
        case .idle: status = .idle
        case .loading: status = .loading
        case .playing: status = .playing
        case .paused: status = .paused
        case .buffering: status = .buffering
        case .ended: status = .ended
        case .error(let error):
            status = .error
            return PlayerStateStruct(
                status: .error,
                currentTime: currentTime,
                duration: duration,
                bufferProgress: bufferProgress,
                progress: duration > 0 ? currentTime / duration : 0,
                error: error,
                url: nil
            )
        }

        let progress = duration > 0 ? currentTime / duration : 0
        return PlayerStateStruct(
            status: status,
            currentTime: currentTime,
            duration: duration,
            bufferProgress: bufferProgress,
            progress: progress,
            error: nil,
            url: nil
        )
    }

    /// 便捷属性：是否正在播放
    var isPlaying: Bool {
        status == .playing
    }

    /// 便捷属性：是否正在缓冲
    var isBuffering: Bool {
        status == .buffering || status == .loading
    }

    /// 便捷属性：是否可以播放
    var canPlay: Bool {
        status == .playing || status == .paused || status == .ended
    }

    /// 便捷属性：是否有错误
    var hasError: Bool {
        status == .error || error != nil
    }

    /// 便捷属性：格式化当前时间
    var currentTimeFormatted: String {
        currentTime.timeFormatted()
    }

    /// 便捷属性：格式化总时长
    var durationFormatted: String {
        duration.timeFormatted()
    }

    /// 便捷属性：格式化剩余时间
    var remainingTimeFormatted: String {
        (duration - currentTime).timeFormatted()
    }
}

// MARK: - Equatable 实现

extension PlayerStateStruct {
    static func == (lhs: PlayerStateStruct, rhs: PlayerStateStruct) -> Bool {
        return lhs.status == rhs.status &&
               lhs.currentTime == rhs.currentTime &&
               lhs.duration == rhs.duration &&
               lhs.bufferProgress == rhs.bufferProgress &&
               lhs.progress == rhs.progress &&
               lhs.url == rhs.url
        // error 不参与比较
    }
}

// MARK: - 播放错误

/// 播放器相关错误类型
enum PlayerError: LocalizedError {
    case invalidURL
    case loadFailed(Error?)
    case playbackFailed(Error?)
    case buffering
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid playback URL"
        case .loadFailed(let error):
            return "Failed to load video: \(error?.localizedDescription ?? "Unknown error")"
        case .playbackFailed(let error):
            return "Playback error: \(error?.localizedDescription ?? "Unknown error")"
        case .buffering:
            return "Buffering..."
        case .unknown:
            return "Unknown playback error"
        }
    }
}

extension PlayerError: Equatable {
    static func == (lhs: PlayerError, rhs: PlayerError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.loadFailed, .loadFailed): return true
        case (.playbackFailed, .playbackFailed): return true
        case (.buffering, .buffering): return true
        case (.unknown, .unknown): return true
        default: return false
        }
    }
}

// MARK: - 统一播放器协议

/// 播放器统一接口协议
/// 整合 PlayerCoreProtocol 和 PlayerEngineProtocol 的功能
@MainActor
protocol Player: AnyObject {
    /// 播放器实例
    var player: AVPlayer { get }

    /// 当前是否正在播放
    var isPlaying: Bool { get }

    /// 当前播放时间（秒）
    var currentTime: Double { get }

    /// 媒体总时长（秒）
    var duration: Double? { get }

    /// 统一状态流（单一数据源）
    var unifiedStatePublisher: AnyPublisher<PlayerStateStruct, Never> { get }

    /// 播放进度流
    var progressPublisher: AnyPublisher<(Double, Double), Never> { get }

    /// 缓冲状态流
    var bufferingPublisher: AnyPublisher<Bool, Never> { get }

    /// 错误流
    var errorPublisher: AnyPublisher<PlayerError, Never> { get }

    /// 开始播放指定 URL 的视频
    func play(url: URL)

    /// 暂停播放
    func pause()

    /// 恢复播放
    func resume()

    /// 停止播放并释放资源
    func stop()

    /// 跳转到指定时间
    func seek(to seconds: Double)

    /// 立即跳转
    func seekImmediate(to seconds: Double)

    /// 添加时间观察者
    func addTimeObserver(handler: @escaping @MainActor (Double, Double) -> Void)

    /// 清理播放器资源
    func cleanup()

    /// 附加播放器层
    func attachPlayerLayer(_ layer: AVPlayerLayer)

    /// 分离播放器层
    func detachPlayerLayer()
}

// MARK: - PlayerCore 协议（保持向后兼容）

/// 播放器核心接口协议（保持向后兼容）
/// 新代码应使用 Player 协议
@MainActor
protocol PlayerCoreProtocol: Player {
    /// 当前播放状态（保持向后兼容）
    var state: PlayerState { get }

    /// 播放结束回调
    var onPlaybackEnded: (() -> Void)? { get set }

    /// 错误回调
    var onError: ((PlayerError) -> Void)? { get set }

    /// 缓冲状态回调
    var onBuffering: ((Bool) -> Void)? { get set }

    /// 准备播放完成回调
    var onReadyToPlay: (() -> Void)? { get set }
}

// MARK: - GestureManager 协议

/// 手势管理器协议
protocol GestureManagerProtocol: AnyObject {
    init(view: UIView, player: AVPlayer)
}

// MARK: - URL 验证器协议

/// URL 验证器协议
protocol URLValidatorProtocol {
    /// 验证 URL 字符串是否有效
    func validate(_ urlString: String) -> Bool
}

// MARK: - 默认 URL 验证器

/// 默认 URL 验证器实现
class DefaultURLValidator: URLValidatorProtocol {
    private let supportedSchemes = ["http", "https", "rtsp", "rtmp"]

    func validate(_ urlString: String) -> Bool {
        guard !urlString.isEmpty else { return false }

        guard let url = URL(string: urlString) else { return false }

        // 检查协议
        guard let scheme = url.scheme?.lowercased(),
              supportedSchemes.contains(scheme) else { return false }

        // 检查主机
        guard url.host != nil else { return false }

        // 检查路径（对于 HLS）
        let path = url.path
        if path.contains(".m3u8") || path.contains("stream") {
            return true
        }

        // 允许其他有效 URL
        return true
    }
}
