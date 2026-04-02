import Foundation
import os.log

// MARK: - 日志级别
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

// MARK: - 日志系统
struct Logger {

    // 日志输出配置
    static var enabled: Bool = true
    static var minLevel: LogLevel = .debug
    
    // 文件日志配置
    static var enableFileLogging: Bool = false  // 生产环境默认关闭
    private static let fileLoggerQueue = DispatchQueue(label: "com.videoplayer.logger.file", qos: .utility)

    private static let subsystem = Bundle.main.bundleIdentifier ?? "VideoPlayer"

    private static let logger = os.Logger(subsystem: subsystem, category: "App")

    // 日志级别阈值
    private static let levelOrder: [LogLevel: Int] = [
        .debug: 0,
        .info: 1,
        .warning: 2,
        .error: 3
    ]

    // 需要过滤的敏感参数
    private static let sensitiveParams = ["api_key", "token", "password", "auth", "secret", "credential"]
    
    // 敏感路径模式（路径中可能包含敏感信息）
    private static let sensitivePathPatterns = [
        "api_key=[^&]+",
        "token=[^&]+",
        "auth=[^&]+"
    ]

    private static func shouldLog(_ level: LogLevel) -> Bool {
        guard enabled else { return false }
        return (levelOrder[level] ?? 0) >= (levelOrder[minLevel] ?? 0)
    }

    /// 过滤URL中的敏感参数
    private static func sanitizeURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            // 尝试用正则过滤路径中的敏感信息
            return sanitizePathTokens(urlString)
        }

        var sanitizedQueryItems: [URLQueryItem] = []
        for item in components.queryItems ?? [] {
            if sensitiveParams.contains(where: { item.name.lowercased().contains($0) }) {
                sanitizedQueryItems.append(URLQueryItem(name: item.name, value: "***REDACTED***"))
            } else {
                sanitizedQueryItems.append(item)
            }
        }

        var newComponents = components
        newComponents.queryItems = sanitizedQueryItems
        return newComponents.url?.absoluteString ?? sanitizePathTokens(urlString)
    }
    
    /// 过滤路径中的敏感令牌
    private static func sanitizePathTokens(_ urlString: String) -> String {
        var sanitized = urlString
        for pattern in sensitivePathPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "***REDACTED***",
                options: .regularExpression
            )
        }
        return sanitized
    }

    // MARK: - 通用日志方法
    private static func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog(level) else { return }

        let fileName = (file as NSString).lastPathComponent

        #if DEBUG
        let logMessage = "[\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"
        print(logMessage)
        #endif

        // 使用 OSLog（生产环境）
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            // 错误日志使用 private 保护敏感信息
            logger.error("\(message, privacy: .private)")
        }
        
        // 文件日志（异步写入）
        if enableFileLogging {
            writeToFile(level: level, message: message, fileName: fileName, line: line)
        }
    }
    
    // MARK: - 文件日志
    private static var logFileURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent("logs/app.log")
    }
    
    private static func writeToFile(level: LogLevel, message: String, fileName: String, line: Int) {
        fileLoggerQueue.async {
            guard let fileURL = logFileURL else { return }
            
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logLine = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"
            
            // 如果文件过大，截断
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? Int64,
               size > 5 * 1024 * 1024 {  // 5MB
                try? "".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            if let data = logLine.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }
    
    /// 清理日志文件
    static func cleanupLogs(maxAge: TimeInterval = 7 * 24 * 60 * 60) {
        fileLoggerQueue.async {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return
            }
            
            let logsDir = caches.appendingPathComponent("logs")
            let cutoffDate = Date().addingTimeInterval(-maxAge)
            
            guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey]) else {
                return
            }
            
            for file in files {
                if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = attributes.creationDate,
                   creationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    // MARK: - 便捷方法
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    // MARK: - 模块化日志
    struct Network {
        static func request(_ method: String, path: String) {
            info("[\(method)] \(path)")
        }

        static func response(_ statusCode: Int, path: String) {
            if statusCode >= 400 {
                Logger.error("Response [\(statusCode)] \(path)")
            } else {
                debug("Response [\(statusCode)] \(path)")
            }
        }

        static func networkError(_ error: Error) {
            Logger.error("Network error: \(error.localizedDescription)")
        }
    }

    struct Auth {
        static func loginAttempt(_ username: String) {
            info("Login attempt for user: \(username)")
        }

        static func loginSuccess(_ username: String) {
            info("Login success: \(username)")
        }

        static func loginFailed(_ error: Error) {
            warning("Login failed: \(error.localizedDescription)")
        }

        static func logout() {
            info("User logged out")
        }
    }

    struct Player {
        static func play(url: String) {
            let sanitizedURL = sanitizeURL(url)
            info("Playing: \(sanitizedURL)")
        }

        static func pause() {
            debug("Playback paused")
        }

        static func stop() {
            info("Playback stopped")
        }

        static func playbackError(_ error: Error) {
            Logger.error("Playback error: \(error.localizedDescription)")
        }
    }

    struct Navigation {
        static func navigateToLogin() {
            info("Navigated to Login")
        }

        static func navigateToHome() {
            info("Navigated to Home")
        }

        static func navigateToPlayer(url: String) {
            let sanitizedURL = sanitizeURL(url)
            info("Navigated to Player: \(sanitizedURL)")
        }
    }
}
