import Foundation
import UIKit

// MARK: - 统一错误展示信息
/// 包含错误展示所需的所有信息
struct ErrorDisplayInfo {
    /// 用户友好的错误消息
    let message: String
    /// 恢复建议
    let recoverySuggestion: String?
    /// 是否可重试
    let isRetryable: Bool
    /// 是否需要登出
    let shouldLogout: Bool
    /// 错误分类
    let category: NetworkErrorCategory
    /// 原始错误
    let underlyingError: Error?

    /// 从任意错误创建展示信息
    static func from(_ error: Error) -> ErrorDisplayInfo {
        // 提取底层错误
        let relevantError = extractRelevantError(from: error)

        // 处理 NetworkError
        if let networkError = relevantError as? NetworkError {
            return ErrorDisplayInfo(
                message: networkError.errorDescription ?? "Network error occurred",
                recoverySuggestion: nil,
                isRetryable: networkError.isRetryable,
                shouldLogout: networkError.shouldLogout,
                category: networkError.category,
                underlyingError: networkError
            )
        }

        // 处理 JellyfinError
        if let jellyfinError = relevantError as? JellyfinError {
            return ErrorDisplayInfo(
                message: jellyfinError.errorDescription ?? "An error occurred",
                recoverySuggestion: jellyfinError.recoverySuggestion,
                isRetryable: jellyfinError.isRetryable,
                shouldLogout: jellyfinError.shouldLogout,
                category: jellyfinError.category,
                underlyingError: jellyfinError
            )
        }

        // 未知错误
        return ErrorDisplayInfo(
            message: relevantError.localizedDescription,
            recoverySuggestion: nil,
            isRetryable: false,
            shouldLogout: false,
            category: .unknown,
            underlyingError: relevantError
        )
    }

    /// 从错误链中提取最相关的错误
    private static func extractRelevantError(from error: Error) -> Error {
        if let urlError = error as? URLError,
           let underlyingError = urlError.userInfo[NSUnderlyingErrorKey] as? Error {
            return extractRelevantError(from: underlyingError)
        }
        return error
    }
}

// MARK: - 错误操作
/// 定义可执行的错误操作
struct ErrorAction {
    enum ActionType {
        case retry
        case logout
        case settings
        case dismiss
    }

    let type: ActionType
    let title: String
    let handler: () -> Void

    static func retry(_ handler: @escaping () -> Void) -> ErrorAction {
        ErrorAction(type: .retry, title: "Retry", handler: handler)
    }

    static func logout(_ handler: @escaping () -> Void) -> ErrorAction {
        ErrorAction(type: .logout, title: "Re-login", handler: handler)
    }
}

// MARK: - 统一错误处理协议
/// 统一的错误处理接口
protocol ErrorHandler: AnyObject {
    /// 处理错误并返回展示信息
    func handle(_ error: Error) -> ErrorDisplayInfo

    /// 记录并处理错误
    func logAndHandle(_ error: Error) -> ErrorDisplayInfo
}

// MARK: - 默认错误处理器
final class DefaultErrorHandler: ErrorHandler {

    static let shared = DefaultErrorHandler()

    private init() {}

    func handle(_ error: Error) -> ErrorDisplayInfo {
        ErrorDisplayInfo.from(error)
    }

    func logAndHandle(_ error: Error) -> ErrorDisplayInfo {
        let info = handle(error)
        Logger.error("Error: \(info.message)")
        return info
    }
}

// MARK: - 错误展示协议
/// UI 错误展示协议
protocol ErrorDisplayable: AnyObject {
    func showError(_ message: String, recoverySuggestion: String?, actions: [ErrorAction])
}

// MARK: - 错误上下文
/// 用于描述错误发生的上下文
struct ErrorContext {
    /// 来源模块
    let source: String
    /// 操作名称
    let operation: String
    
    /// 便捷初始化
    init(source: String, operation: String) {
        self.source = source
        self.operation = operation
    }
    
    /// 预定义的上下文
    static let playerLoad = ErrorContext(source: "PlayerEngine", operation: "loadVideo")
    static let networkRequest = ErrorContext(source: "NetworkManager", operation: "request")
    static let authentication = ErrorContext(source: "Auth", operation: "login")
    static let cacheOperation = ErrorContext(source: "CacheSystem", operation: "cache")
}

// MARK: - 错误处理辅助类
enum ErrorHandling {

    /// 处理错误（便捷方法）
    static func handle(_ error: Error) -> ErrorDisplayInfo {
        DefaultErrorHandler.shared.handle(error)
    }

    /// 记录并处理错误（便捷方法）
    static func logAndHandle(_ error: Error) -> ErrorDisplayInfo {
        DefaultErrorHandler.shared.logAndHandle(error)
    }
    
    /// 统一错误处理入口 - 带上下文
    /// - Parameters:
    ///   - error: 错误对象
    ///   - context: 错误上下文
    /// - Returns: 错误展示信息
    static func handle(_ error: Error, context: ErrorContext) -> ErrorDisplayInfo {
        let info = handle(error)
        
        // 使用结构化日志记录
        Logger.error("[\(context.source)] \(context.operation) failed: \(info.message)")
        
        // 根据上下文添加额外信息
        if info.underlyingError != nil {
            Logger.debug("[\(context.source)] Underlying error: \(type(of: info.underlyingError!))")
        }
        
        return info
    }
    
    /// 统一错误处理入口 - 带操作和重试
    /// - Parameters:
    ///   - error: 错误对象
    ///   - context: 错误上下文
    ///   - retryHandler: 可选的重新尝试处理
    ///   - logoutHandler: 可选的登出处理
    /// - Returns: 错误展示信息和可选的操作
    static func handleWithActions(
        _ error: Error,
        context: ErrorContext,
        retryHandler: (() -> Void)? = nil,
        logoutHandler: (() -> Void)? = nil
    ) -> (info: ErrorDisplayInfo, actions: [ErrorAction]) {
        let info = handle(error, context: context)
        var actions: [ErrorAction] = []
        
        // 重试按钮
        if info.isRetryable, let retry = retryHandler {
            actions.append(.retry(retry))
        }
        
        // 登出按钮
        if info.shouldLogout, let logout = logoutHandler {
            actions.append(.logout(logout))
        }
        
        return (info, actions)
    }

    /// 构建错误操作列表
    static func buildActions(
        error: Error,
        retryAction: (() -> Void)?,
        logoutAction: (() -> Void)?
    ) -> [ErrorAction] {
        let info = handle(error)
        var actions: [ErrorAction] = []

        // 重试按钮
        if info.isRetryable, let retry = retryAction {
            actions.append(.retry(retry))
        }

        // 登出按钮
        if info.shouldLogout, let logout = logoutAction {
            actions.append(.logout(logout))
        }

        return actions
    }

    /// 构建 UIAlertAction 列表
    static func buildAlertActions(
        error: Error,
        retryAction: (() -> Void)?,
        logoutAction: (() -> Void)?
    ) -> [UIAlertAction] {
        buildActions(error: error, retryAction: retryAction, logoutAction: logoutAction)
            .map { action in
                let style: UIAlertAction.Style = action.type == .dismiss ? .cancel : .default
                return UIAlertAction(title: action.title, style: style) { _ in
                    action.handler()
                }
            }
    }
}

// MARK: - 错误转换扩展
extension Error {
    /// 将错误转换为网络错误（如果是）
    var asNetworkError: NetworkError? {
        self as? NetworkError
    }

    /// 将错误转换为 Jellyfin 错误（如果是）
    var asJellyfinError: JellyfinError? {
        self as? JellyfinError
    }
}