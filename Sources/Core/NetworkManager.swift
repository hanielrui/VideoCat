import Foundation
import Network

// MARK: - 网络错误分层
/// 分类：
/// - ClientError: 客户端错误（URL、参数、编码等）
/// - NetworkError: 网络层错误（无网络、超时、连接失败）
/// - ServerError: 服务器端错误（4xx、5xx）
/// - AuthError: 认证授权错误（401、403）
/// - UnknownError: 未知错误

// MARK: - 错误分类
enum NetworkErrorCategory {
    case client      // 客户端错误
    case network     // 网络层错误
    case server      // 服务器错误
    case auth        // 认证授权错误
    case unknown     // 未知错误
}

// MARK: - 详细错误枚举
enum NetworkError: LocalizedError {
    // MARK: - 客户端错误（Client Error）
    case emptyURL
    case invalidURL(String)
    case invalidParameters(String)
    case encodingFailed(String)
    
    // MARK: - 网络层错误（Network Error）
    case noNetwork
    case networkUnreachable
    case timeout
    case connectionFailed(String)
    case cancelled
    
    // MARK: - 服务器错误（Server Error）
    case serverError(statusCode: Int, message: String?)
    case badRequest(message: String?)          // 400
    case notFound(resource: String)             // 404
    case conflict(String)                       // 409
    case serverUnavailable                       // 503
    case internalServerError                     // 500
    
    // MARK: - 认证授权错误（Auth Error）
    case unauthorized(message: String?)          // 401
    case forbidden(reason: String?)              // 403
    case tokenExpired
    case tokenInvalid
    case accessDenied(reason: String?)
    
    // MARK: - 解码错误（Decoding Error）
    case decodingError(String)
    case unexpectedResponse
    case emptyResponse
    
    // MARK: - 未知错误
    case unknown(underlying: Error?)
    
    // MARK: - 分类属性
    var category: NetworkErrorCategory {
        switch self {
        case .emptyURL, .invalidURL, .invalidParameters, .encodingFailed:
            return .client
        case .noNetwork, .networkUnreachable, .timeout, .connectionFailed, .cancelled:
            return .network
        case .serverError, .badRequest, .notFound, .conflict, .serverUnavailable, .internalServerError:
            return .server
        case .unauthorized, .forbidden, .tokenExpired, .tokenInvalid, .accessDenied:
            return .auth
        case .decodingError, .unexpectedResponse, .emptyResponse, .unknown:
            return .unknown
        }
    }
    
    // MARK: - HTTP 状态码（如果有）
    var httpStatusCode: Int? {
        switch self {
        case .badRequest: return 400
        case .unauthorized: return 401
        case .forbidden: return 403
        case .notFound: return 404
        case .conflict: return 409
        case .internalServerError: return 500
        case .serverUnavailable: return 503
        case .serverError(let code, _): return code
        default: return nil
        }
    }
    
    // MARK: - 是否可重试
    var isRetryable: Bool {
        switch self {
        case .timeout, .connectionFailed, .serverUnavailable, .noNetwork, .networkUnreachable:
            return true
        case .serverError(let code, _):
            return code >= 500  // 5xx 可重试
        default:
            return false
        }
    }

    // MARK: - 是否需要登出（认证错误）
    var shouldLogout: Bool {
        switch self {
        case .unauthorized, .forbidden, .tokenExpired, .tokenInvalid, .accessDenied:
            return true
        default:
            return false
        }
    }
    
    // MARK: - LocalizedError
    var errorDescription: String? {
        switch self {
        // Client
        case .emptyURL:
            return "Server URL is empty"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidParameters(let msg):
            return "Invalid parameters: \(msg)"
        case .encodingFailed(let msg):
            return "Encoding failed: \(msg)"
            
        // Network
        case .noNetwork:
            return "No network connection"
        case .networkUnreachable:
            return "Network is unreachable"
        case .timeout:
            return "Request timed out"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .cancelled:
            return "Request was cancelled"
            
        // Server
        case .serverError(let code, let msg):
            return msg ?? "Server error: \(code)"
        case .badRequest(let msg):
            return msg ?? "Bad request"
        case .notFound(let resource):
            return "Resource not found: \(resource)"
        case .conflict(let msg):
            return msg ?? "Conflict"
        case .serverUnavailable:
            return "Service unavailable"
        case .internalServerError:
            return "Internal server error"
            
        // Auth
        case .unauthorized(let msg):
            return msg ?? "Unauthorized"
        case .forbidden(let reason):
            return reason ?? "Access forbidden"
        case .tokenExpired:
            return "Token expired"
        case .tokenInvalid:
            return "Token invalid"
        case .accessDenied(let reason):
            return reason ?? "Access denied"
            
        // Decoding
        case .decodingError(let msg):
            return "Decoding error: \(msg)"
        case .unexpectedResponse:
            return "Unexpected response format"
        case .emptyResponse:
            return "Empty response"
            
        // Unknown
        case .unknown(let error):
            return error?.localizedDescription ?? "Unknown error"
        }
    }
    
    // MARK: - 便捷初始化（从 HTTP 响应创建）
    static func from(httpResponse: HTTPURLResponse, data: Data? = nil) -> NetworkError {
        let statusCode = httpResponse.statusCode
        let message = data.flatMap { String(data: $0, encoding: .utf8) }
        
        switch statusCode {
        case 400:
            return .badRequest(message: message)
        case 401:
            return .unauthorized(message: message)
        case 403:
            return .forbidden(reason: message)
        case 404:
            return .notFound(resource: httpResponse.url?.path ?? "unknown")
        case 409:
            return .conflict(message)
        case 500...599:
            return .serverError(statusCode: statusCode, message: message)
        default:
            return .serverError(statusCode: statusCode, message: message)
        }
    }
    
    // MARK: - 便捷初始化（从 Error 创建）
    static func from(_ error: Error) -> NetworkError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .noNetwork
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            case .cannotFindHost, .cannotConnectToHost, .serverCertificateUntrusted:
                return .connectionFailed(urlError.localizedDescription)
            case .notReachable:
                return .networkUnreachable
            default:
                return .unknown(underlying: error)
            }
        }
        
        if let networkError = error as? NetworkError {
            return networkError
        }
        
        return .unknown(underlying: error)
    }
}

// MARK: - 请求配置
struct RequestConfig {
    var contentType: String = APIConstants.ContentType.json
    var headers: [String: String] = [:]
    var timeoutInterval: TimeInterval = AppConstants.Timeout.defaultRequest
    var queryParams: [String: String]? = nil

    init(
        contentType: String = APIConstants.ContentType.json,
        headers: [String: String] = [:],
        timeoutInterval: TimeInterval = AppConstants.Timeout.defaultRequest,
        queryParams: [String: String]? = nil
    ) {
        self.contentType = contentType
        self.headers = headers
        self.timeoutInterval = timeoutInterval
        self.queryParams = queryParams
    }

    init(endpoint: Endpoint) {
        self.contentType = endpoint.contentType
        self.headers = endpoint.headers ?? [:]
        self.timeoutInterval = endpoint.timeoutInterval
        self.queryParams = endpoint.queryParams
    }
}

// MARK: - 网络服务协议（统一接口）
/// 网络服务抽象接口
protocol NetworkService {
    var baseURL: String { get set }
    var token: String { get set }

    // 原有方法（保持向后兼容）
    func request(path: String, method: String, body: Data?, config: RequestConfig) async throws -> Data
    func request<T: Decodable>(path: String, method: String, body: Data?, config: RequestConfig) async throws -> T

    // 新方法：基于 Endpoint 的请求
    func request(_ endpoint: Endpoint) async throws -> Data
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T

    // URL 构建器访问
    var urlBuilder: URLBuilder { get }
}

// MARK: - 网络管理器
class NetworkManager: NetworkService {

    // MARK: - 单例
    static let shared = NetworkManager()

    // MARK: - 属性
    var baseURL: String = "" {
        didSet {
            let normalized = URLBuilder.normalize(baseURL)
            if normalized != baseURL {
                baseURL = normalized
            }
            urlBuilder = URLBuilder(baseURL: baseURL)
            Logger.info("Base URL set to: \(self.baseURL)")
        }
    }

    var token: String = ""

    // MARK: - 内部组件（可注入）
    private(set) var urlBuilder: URLBuilder
    private let session: URLSession
    private let networkMonitor: NetworkMonitor

    // MARK: - 拦截器链
    private var interceptorChain: NetworkInterceptor?
    private var loggingInterceptor: LoggingInterceptor?
    private var timingInterceptor: TimingInterceptor?

    // MARK: - 初始化
    init() {
        self.urlBuilder = URLBuilder(baseURL: "")
        self.session = .shared
        self.networkMonitor = .shared
        setupDefaultInterceptors()
    }

    // 可注入初始化（单元测试）
    init(
        session: URLSession,
        urlBuilder: URLBuilder,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.urlBuilder = urlBuilder
        self.session = session
        self.networkMonitor = networkMonitor
        setupDefaultInterceptors()
    }

    // MARK: - 拦截器配置

    /// 设置默认拦截器链
    private func setupDefaultInterceptors() {
        // 日志拦截器
        loggingInterceptor = LoggingInterceptor(level: .basic)
        timingInterceptor = TimingInterceptor()

        // Token 拦截器
        let tokenInterceptor = TokenInterceptor(tokenProvider: { [weak self] in
            self?.token ?? ""
        })

        // 重试拦截器
        let retryInterceptor = RetryInterceptor()

        // 构建拦截器链（顺序重要：日志 -> Token -> 重试）
        interceptorChain = CompositeInterceptor([
            loggingInterceptor!,
            tokenInterceptor,
            retryInterceptor
        ])
    }

    /// 手动配置拦截器链
    func setInterceptorChain(_ chain: NetworkInterceptor) {
        self.interceptorChain = chain
    }

    /// 添加拦截器到链首
    func prependInterceptor(_ interceptor: NetworkInterceptor) {
        guard let existingChain = interceptorChain else {
            interceptorChain = interceptor
            return
        }

        if let composite = existingChain as? CompositeInterceptor {
            // 扩展现有组合
            // 这里简化处理，重新创建组合
            let newInterceptors = [interceptor] + [existingChain]
            interceptorChain = CompositeInterceptor(newInterceptors)
        } else {
            interceptorChain = CompositeInterceptor([interceptor, existingChain])
        }
    }

    // MARK: - 请求方法
    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        config: RequestConfig = RequestConfig()
    ) async throws -> Data {

        // 构建 URL
        let url = try urlBuilder.build(path: path, queryParams: config.queryParams)

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = config.timeoutInterval
        request.setValue(config.contentType, forHTTPHeaderField: APIConstants.Headers.contentType)

        // 添加自定义 Headers
        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 添加请求体
        request.httpBody = body

        // 通过拦截器链处理请求
        if let chain = interceptorChain {
            request = await chain.adapt(request)
        }

        // 记录请求开始时间
        timingInterceptor?.adapt(request)

        // 发送请求并处理重试
        let (data, httpResponse) = try await sendWithRetry(request: request, config: config)

        // 记录完成时间和响应日志
        timingInterceptor?.recordCompletion(for: request.url!)
        if let response = httpResponse {
            loggingInterceptor?.logResponse(statusCode: response.statusCode, data: data, path: path)
        }

        return data
    }

    /// 发送请求并处理重试
    private func sendWithRetry(request: URLRequest, config: RequestConfig) async throws -> (Data, HTTPURLResponse?) {
        // 检查网络状态
        guard networkMonitor.isConnected else {
            throw NetworkError.noNetwork
        }

        var currentRequest = request
        var lastError: Error?

        // 最多重试次数 + 1 次（初始尝试）
        let maxAttempts = 3

        for attempt in 0..<maxAttempts {
            do {
                // 更新重试计数
                currentRequest.retryCount = attempt

                // 发送请求
                let (data, response) = try await session.data(for: currentRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.unknown(NSError(domain: "Invalid response", code: -1))
                }

                // 检查是否需要重试（拦截器决定）
                if httpResponse.statusCode >= 400 {
                    let error = NetworkError.from(httpResponse: httpResponse, data: data)

                    // 记录错误日志
                    loggingInterceptor?.logError(error, path: currentRequest.url?.path ?? "")

                    // 检查拦截器是否应该重试
                    if let chain = interceptorChain {
                        let shouldRetry = await chain.retry(currentRequest, error: error)
                        if shouldRetry && error.isRetryable && attempt < maxAttempts - 1 {
                            continue // 继续重试
                        }
                    }

                    throw error
                }

                return (data, httpResponse)

            } catch {
                lastError = error

                // 检查拦截器是否应该重试
                if let chain = interceptorChain {
                    let shouldRetry = await chain.retry(currentRequest, error: error)
                    if shouldRetry && attempt < maxAttempts - 1 {
                        continue // 继续重试
                    }
                }

                // 不重试或已达最大次数
                throw error
            }
        }

        throw lastError ?? NetworkError.unknown(NSError(domain: "Request failed", code: -1))
    }

    // MARK: - 泛型请求
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        config: RequestConfig = RequestConfig()
    ) async throws -> T {

        let data = try await request(path: path, method: method, body: body, config: config)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.error("Decoding error: \(error.localizedDescription)")
            throw NetworkError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - 基于 Endpoint 的请求
    func request(_ endpoint: Endpoint) async throws -> Data {
        let config = RequestConfig(endpoint: endpoint)
        return try await request(
            path: endpoint.path,
            method: endpoint.method.rawValue,
            body: endpoint.body,
            config: config
        )
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let config = RequestConfig(endpoint: endpoint)
        return try await request(
            path: endpoint.path,
            method: endpoint.method.rawValue,
            body: endpoint.body,
            config: config
        )
    }

    // MARK: - 便捷方法
    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET")
    }

    func post<T: Decodable>(_ path: String, body: Data?) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }
}
