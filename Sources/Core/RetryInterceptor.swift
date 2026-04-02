import Foundation
import ObjectiveC

// MARK: - 重试拦截器

/// 重试拦截器
/// 自动对失败的请求进行重试
final class RetryInterceptor: NetworkInterceptor {

    // MARK: - 配置

    struct Config {
        /// 最大重试次数
        var maxRetries: Int
        /// 重试间隔（秒）
        var retryInterval: TimeInterval
        /// 可重试的错误类型
        var retryableErrors: [RetryableError]

        static let `default` = Config(
            maxRetries: 3,
            retryInterval: 1.0,
            retryableErrors: [.timeout, .noNetwork, .serverError]
        )
    }

    // MARK: - 可重试错误类型

    enum RetryableError {
        case timeout       // 超时
        case noNetwork     // 无网络
        case serverError   // 服务器错误 (5xx)
        case rateLimited   // 限流 (429)
    }

    // MARK: - 属性

    private let config: Config
    private let exponentialBackoff: Bool

    // MARK: - 初始化

    /// 初始化重试拦截器
    /// - Parameters:
    ///   - config: 重试配置
    ///   - exponentialBackoff: 是否使用指数退避
    init(config: Config = .default, exponentialBackoff: Bool = true) {
        self.config = config
        self.exponentialBackoff = exponentialBackoff
    }

    // MARK: - NetworkInterceptor

    /// 请求适配：不做处理
    func adapt(_ request: URLRequest) async -> URLRequest {
        request
    }

    /// 错误拦截：判断是否应该重试
    func retry(_ request: URLRequest, error: Error) async -> Bool {
        // 检查是否可重试
        guard shouldRetry(error: error) else {
            return false
        }

        // 获取重试次数（通过 UserInfo）
        let currentRetry = request.retryCount

        // 检查是否超过最大重试次数
        guard currentRetry < config.maxRetries else {
            Logger.warning("Max retries reached (\(config.maxRetries))")
            return false
        }

        // 计算延迟（支持指数退避）
        let delay = calculateDelay(retryCount: currentRetry)

        Logger.info("Scheduling retry \(currentRetry + 1)/\(config.maxRetries) after \(delay)s")

        // 等待后重试
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        return true
    }

    // MARK: - 私有方法

    private func shouldRetry(error: Error) -> Bool {
        guard let networkError = error as? NetworkError else {
            return false
        }

        for retryableError in config.retryableErrors {
            switch retryableError {
            case .timeout:
                if case .timeout = networkError {
                    return true
                }
            case .noNetwork:
                if case .noNetwork = networkError {
                    return true
                }
            case .serverError:
                if case .serverError(let code, _) = networkError, (500...599).contains(code) {
                    return true
                }
            case .rateLimited:
                if case .serverError(let code, _) = networkError, code == 429 {
                    return true
                }
            }
        }

        return false
    }

    private func calculateDelay(retryCount: Int) -> TimeInterval {
        if exponentialBackoff {
            // 指数退避：1s, 2s, 4s, 8s...
            return config.retryInterval * pow(2.0, Double(retryCount))
        } else {
            // 固定间隔
            return config.retryInterval
        }
    }
}

// MARK: - URLRequest 扩展 - 使用关联对象存储用户信息

private var httpUserInfoKey: UInt8 = 0

extension URLRequest {
    /// 关联用户信息（用于存储重试计数等）
    private var httpUserInfo: [String: Any]? {
        get {
            objc_getAssociatedObject(self, &httpUserInfoKey) as? [String: Any]
        }
        set {
            objc_setAssociatedObject(
                self,
                &httpUserInfoKey,
                newValue,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )
        }
    }
    
    /// 重试次数
    var retryCount: Int {
        get { httpUserInfo?["retryCount"] as? Int ?? 0 }
        set {
            var userInfo = httpUserInfo ?? [:]
            userInfo["retryCount"] = newValue
            httpUserInfo = userInfo
        }
    }
}