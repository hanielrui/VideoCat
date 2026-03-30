import Foundation

// MARK: - 请求分发器
class RequestDispatcher {

    private let session: URLSession
    private let urlBuilder: URLBuilder
    private let networkMonitor: NetworkMonitor

    init(
        session: URLSession = .shared,
        urlBuilder: URLBuilder,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.session = session
        self.urlBuilder = urlBuilder
        self.networkMonitor = networkMonitor
    }

    // MARK: - 发送请求
    func send(
        path: String,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers: [String: String]? = nil,
        config: RequestConfig = RequestConfig()
    ) async throws -> Data {

        Logger.Network.request(method.rawValue, path: path)

        // 检查网络
        guard networkMonitor.isConnected else {
            Logger.warning("No network connection")
            throw NetworkError.noNetwork
        }

        // 构建 URL
        let url = try urlBuilder.build(path: path, queryParams: config.queryParams)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = config.timeoutInterval

        // 设置默认 Headers
        request.addValue(config.contentType, forHTTPHeaderField: APIConstants.Headers.contentType)

        // 设置自定义 Headers
        headers?.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }

        // 设置 Body
        if let body = body {
            request.httpBody = body
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(NSError(domain: "Invalid response", code: -1))
            }

            Logger.Network.response(httpResponse.statusCode, path: path)

            // 处理错误状态码
            if httpResponse.statusCode == 401 {
                throw NetworkError.httpError(statusCode: 401)
            }

            if httpResponse.statusCode >= 400 {
                throw NetworkError.httpError(statusCode: httpResponse.statusCode)
            }

            return data

        } catch let error as NetworkError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw NetworkError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.noNetwork
            default:
                throw NetworkError.unknown(error)
            }
        }
    }

    // MARK: - 泛型请求
    func send<T: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        body: Data? = nil,
        headers: [String: String]? = nil,
        config: RequestConfig = RequestConfig()
    ) async throws -> T {

        let data = try await send(path: path, method: method, body: body, headers: headers, config: config)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.error("Decoding error: \(error.localizedDescription)")
            throw NetworkError.decodingError(error)
        }
    }
}

// MARK: - HTTP 方法
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}
