import Foundation

// MARK: - HTTP 方法
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// MARK: - Endpoint 协议
/// 定义 API 端点的协议，支持灵活的请求配置
protocol Endpoint {
    /// 路径（不含 baseURL）
    var path: String { get }

    /// HTTP 方法
    var method: HTTPMethod { get }

    /// 查询参数
    var queryParams: [String: String]? { get }

    /// 请求头
    var headers: [String: String]? { get }

    /// 请求体
    var body: Data? { get }

    /// 超时时间
    var timeoutInterval: TimeInterval { get }

    /// 内容类型
    var contentType: String { get }
}

// MARK: - Endpoint 默认实现
extension Endpoint {
    var method: HTTPMethod { .get }
    var queryParams: [String: String]? { nil }
    var headers: [String: String]? { nil }
    var body: Data? { nil }
    var timeoutInterval: TimeInterval { AppConstants.Timeout.defaultRequest }
    var contentType: String { APIConstants.ContentType.json }
}

// MARK: - 便捷构建器
/// 用于创建 Endpoint 的便捷结构体
struct APIEndpoint: Endpoint {
    let path: String
    let method: HTTPMethod
    let queryParams: [String: String]?
    let headers: [String: String]?
    let body: Data?
    let timeoutInterval: TimeInterval
    let contentType: String

    init(
        path: String,
        method: HTTPMethod = .get,
        queryParams: [String: String]? = nil,
        headers: [String: String]? = nil,
        body: Data? = nil,
        timeoutInterval: TimeInterval = AppConstants.Timeout.defaultRequest,
        contentType: String = APIConstants.ContentType.json
    ) {
        self.path = path
        self.method = method
        self.queryParams = queryParams
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
        self.contentType = contentType
    }

    // MARK: - 便捷静态方法
    static func get(_ path: String, queryParams: [String: String]? = nil) -> APIEndpoint {
        APIEndpoint(path: path, method: .get, queryParams: queryParams)
    }

    static func post(_ path: String, body: Data?, contentType: String = APIConstants.ContentType.json) -> APIEndpoint {
        APIEndpoint(path: path, method: .post, body: body, contentType: contentType)
    }

    static func put(_ path: String, body: Data?) -> APIEndpoint {
        APIEndpoint(path: path, method: .put, body: body)
    }

    static func delete(_ path: String) -> APIEndpoint {
        APIEndpoint(path: path, method: .delete)
    }
}
