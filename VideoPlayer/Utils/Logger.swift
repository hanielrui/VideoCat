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

    private static let subsystem = Bundle.main.bundleIdentifier ?? "VideoPlayer"

    private static let logger = os.Logger(subsystem: subsystem, category: "App")

    // 日志级别阈值
    private static let levelOrder: [LogLevel: Int] = [
        .debug: 0,
        .info: 1,
        .warning: 2,
        .error: 3
    ]

    private static func shouldLog(_ level: LogLevel) -> Bool {
        guard enabled else { return false }
        return (levelOrder[level] ?? 0) >= (levelOrder[minLevel] ?? 0)
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
            logger.error("\(message, privacy: .public)")
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
                error("Response [\(statusCode)] \(path)")
            } else {
                debug("Response [\(statusCode)] \(path)")
            }
        }

        static func error(_ error: Error) {
            self.error("Network error: \(error.localizedDescription)")
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
            info("Playing: \(url)")
        }

        static func pause() {
            debug("Playback paused")
        }

        static func stop() {
            info("Playback stopped")
        }

        static func error(_ error: Error) {
            self.error("Playback error: \(error.localizedDescription)")
        }
    }
}
