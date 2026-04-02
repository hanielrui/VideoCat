import Foundation

// MARK: - 日志拦截器

/// 日志拦截器
/// 统一记录请求和响应日志
final class LoggingInterceptor: NetworkInterceptor {

    // MARK: - 日志级别

    enum LogLevel {
        case none       // 不记录日志
        case basic      // 只记录请求和响应
        case detailed   // 记录完整详情（包括请求头、响应体）
    }

    // MARK: - 属性

    private let level: LogLevel
    private let sensitiveParams: [String]

    // MARK: - 初始化

    /// 初始化日志拦截器
    /// - Parameters:
    ///   - level: 日志级别
    ///   - sensitiveParams: 敏感参数列表（会被脱敏）
    init(level: LogLevel = .basic, sensitiveParams: [String] = ["token", "api_key", "password", "auth"]) {
        self.level = level
        self.sensitiveParams = sensitiveParams
    }

    // MARK: - NetworkInterceptor

    /// 请求适配：记录请求信息
    func adapt(_ request: URLRequest) async -> URLRequest {
        guard level != .none else {
            return request
        }

        logRequest(request)
        return request
    }

    /// 错误拦截：记录错误信息
    func retry(_ request: URLRequest, error: Error) async -> Bool {
        // 日志拦截器不决定是否重试，只是记录
        Logger.Network.networkError(error)
        return false
    }

    // MARK: - 日志方法

    private func logRequest(_ request: URLRequest) {
        guard let url = request.url else { return }

        let method = request.httpMethod ?? "GET"
        let path = url.path
        let query = url.query.map { "?\($0)" } ?? ""

        switch level {
        case .none:
            break
        case .basic:
            Logger.Network.request(method, path: path + query)
        case .detailed:
            var logMessage = "→ \(method) \(path)\(query)"
            if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                logMessage += "\n  Headers: \(sanitizeHeaders(headers))"
            }
            if let body = request.httpBody, !body.isEmpty {
                if let bodyString = String(data: body, encoding: .utf8) {
                    logMessage += "\n  Body: \(bodyString)"
                }
            }
            Logger.debug(logMessage)
        }
    }

    /// 记录响应信息（非拦截器方法，由外部调用）
    func logResponse(statusCode: Int, data: Data?, path: String) {
        switch level {
        case .none:
            break
        case .basic:
            Logger.Network.response(statusCode, path: path)
        case .detailed:
            var logMessage = "← Response [\(statusCode)] \(path)"
            if let data = data, !data.isEmpty {
                if let responseString = String(data: data, encoding: .utf8), responseString.count < 500 {
                    logMessage += "\n  Body: \(responseString)"
                } else {
                    logMessage += "\n  Body: <\(data.count) bytes>"
                }
            }
            Logger.debug(logMessage)
        }
    }

    /// 记录错误信息
    func logError(_ error: Error, path: String) {
        Logger.error("Request failed [\(path)]: \(error.localizedDescription)")
    }

    // MARK: - 私有方法

    private func sanitizeHeaders(_ headers: [String: String]) -> [String: String] {
        var sanitized = headers

        for key in sanitized.keys {
            if sensitiveParams.contains(where: { key.lowercased().contains($0) }) {
                sanitized[key] = "***REDACTED***"
            }
        }

        return sanitized
    }
}

// MARK: - 请求计时拦截器（可与日志配合）

/// 请求计时拦截器
/// 记录请求耗时
final class TimingInterceptor: NetworkInterceptor {

    /// 请求开始时间存储
    private var startTimes: [String: Date] = [:]
    private let lock = NSLock()

    func adapt(_ request: URLRequest) async -> URLRequest {
        guard let url = request.url else { return request }

        let key = url.absoluteString
        lock.lock()
        startTimes[key] = Date()
        lock.unlock()

        return request
    }

    func retry(_ request: URLRequest, error: Error) async -> Bool {
        false
    }

    /// 记录请求完成（外部调用）
    func recordCompletion(for url: URL) {
        let key = url.absoluteString

        lock.lock()
        let startTime = startTimes.removeValue(forKey: key)
        lock.unlock()

        if let start = startTime {
            let duration = Date().timeIntervalSince(start)
            Logger.debug("Request completed in \(String(format: "%.2f", duration))s: \(url.lastPathComponent)")
        }
    }
}