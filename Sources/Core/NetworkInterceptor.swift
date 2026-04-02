import Foundation

// MARK: - 网络拦截器协议

/// 网络请求拦截器协议
/// 用于在请求发送前和响应返回后进行拦截处理
/// 支持链式组合，实现职责分离
protocol NetworkInterceptor {
    /// 请求适配（发送前处理）
    /// - Parameter request: 原始请求
    /// - Returns: 适配后的请求
    func adapt(_ request: URLRequest) async -> URLRequest

    /// 错误拦截（响应后处理）
    /// - Parameters:
    ///   - request: 发送的请求
    ///   - error: 响应错误
    /// - Returns: 是否应该重试
    func retry(_ request: URLRequest, error: Error) async -> Bool
}

// MARK: - 拦截器链

/// 拦截器链管理器
/// 按顺序执行多个拦截器
final class InterceptorChain: NetworkInterceptor {

    private let interceptors: [NetworkInterceptor]

    init(_ interceptors: [NetworkInterceptor]) {
        self.interceptors = interceptors
    }

    /// 链式执行请求适配
    func adapt(_ request: URLRequest) async -> URLRequest {
        var currentRequest = request

        for interceptor in interceptors {
            currentRequest = await interceptor.adapt(currentRequest)
        }

        return currentRequest
    }

    /// 链式执行错误拦截（任一拦截器返回 true 表示应该重试）
    func retry(_ request: URLRequest, error: Error) async -> Bool {
        for interceptor in interceptors {
            if await interceptor.retry(request, error: error) {
                return true
            }
        }
        return false
    }
}

// MARK: - 默认空拦截器

/// 默认空拦截器（不做任何处理）
struct EmptyInterceptor: NetworkInterceptor {
    func adapt(_ request: URLRequest) async -> URLRequest {
        request
    }

    func retry(_ request: URLRequest, error: Error) async -> Bool {
        false
    }
}

// MARK: - 复合拦截器

/// 复合拦截器
/// 可以组合多个拦截器为一个
struct CompositeInterceptor: NetworkInterceptor {
    private let interceptors: [NetworkInterceptor]

    init(_ interceptors: [NetworkInterceptor]) {
        self.interceptors = interceptors
    }

    func adapt(_ request: URLRequest) async -> URLRequest {
        var currentRequest = request
        for interceptor in interceptors {
            currentRequest = await interceptor.adapt(currentRequest)
        }
        return currentRequest
    }

    func retry(_ request: URLRequest, error: Error) async -> Bool {
        for interceptor in interceptors {
            if await interceptor.retry(request, error: error) {
                return true
            }
        }
        return false
    }
}