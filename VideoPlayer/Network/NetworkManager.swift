import Foundation
import Network

// MARK: - 自定义错误
enum NetworkError: LocalizedError {
    case emptyURL
    case invalidURL
    case noNetwork
    case timeout
    case httpError(statusCode: Int)
    case decodingError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "Server URL is empty"
        case .invalidURL:
            return "Invalid URL"
        case .noNetwork:
            return "No network connection"
        case .timeout:
            return "Request timed out"
        case .httpError(let code):
            return "HTTP Error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unknown(let error):
            return error.localizedDescription
        }
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
}

// MARK: - 网络服务协议
protocol NetworkServiceProtocol {
    var baseURL: String { get set }
    var token: String { get set }

    func request(path: String, method: String, body: Data?, config: RequestConfig) async throws -> Data
    func request<T: Decodable>(path: String, method: String, body: Data?, config: RequestConfig) async throws -> T
}

// MARK: - 网络管理器
class NetworkManager: NetworkServiceProtocol {

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
    private(set) var dispatcher: RequestDispatcher

    // MARK: - 初始化
    init() {
        self.urlBuilder = URLBuilder(baseURL: "")
        self.dispatcher = RequestDispatcher(urlBuilder: urlBuilder)
    }

    // 可注入初始化（单元测试）
    init(
        session: URLSession,
        urlBuilder: URLBuilder,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.urlBuilder = urlBuilder
        self.dispatcher = RequestDispatcher(
            session: session,
            urlBuilder: urlBuilder,
            networkMonitor: networkMonitor
        )
    }

    // MARK: - 请求方法
    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        config: RequestConfig = RequestConfig()
    ) async throws -> Data {

        var headers = config.headers

        if !token.isEmpty {
            headers[APIConstants.Headers.token] = token
        }

        return try await dispatcher.send(
            path: path,
            method: HTTPMethod(rawValue: method) ?? .get,
            body: body,
            headers: headers,
            config: config
        )
    }

    // MARK: - 泛型请求
    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        config: RequestConfig = RequestConfig()
    ) async throws -> T {

        var headers = config.headers

        if !token.isEmpty {
            headers[APIConstants.Headers.token] = token
        }

        return try await dispatcher.send(
            path: path,
            method: HTTPMethod(rawValue: method) ?? .get,
            body: body,
            headers: headers,
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
