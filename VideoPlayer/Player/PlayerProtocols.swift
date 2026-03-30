import AVFoundation

// MARK: - 播放错误
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

// MARK: - PlayerCore 协议
protocol PlayerCoreProtocol: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var duration: Double? { get }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onError: ((PlayerError) -> Void)? { get set }
    var onBuffering: ((Bool) -> Void)? { get set }
    var onReadyToPlay: (() -> Void)? { get set }

    func play(url: URL)
    func pause()
    func resume()
    func stop()
    func seek(to seconds: Double)
    func addTimeObserver(handler: @escaping (Double, Double) -> Void)
    func cleanup()
}

// MARK: - GestureManager 协议
protocol GestureManagerProtocol: AnyObject {
    init(view: UIView, player: AVPlayer)
}

// MARK: - URL 验证器协议
protocol URLValidatorProtocol {
    func validate(_ urlString: String) -> Bool
}

// MARK: - 默认 URL 验证器
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
