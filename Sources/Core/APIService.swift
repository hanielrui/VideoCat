import Foundation

// MARK: - API 服务协议
/// 抽象的 API 服务层协议，支持任意后端服务
protocol APIServiceProtocol {
    associatedtype EndpointType: Endpoint

    /// 发送请求
    func request<T: Decodable>(_ endpoint: EndpointType) async throws -> T

    /// 发送纯数据请求
    func requestData(_ endpoint: EndpointType) async throws -> Data
}

// MARK: - 基础 API 服务实现
/// 基于 NetworkService 的通用 API 服务实现
class BaseAPIService: APIServiceProtocol {
    typealias EndpointType = APIEndpoint

    private let networkService: NetworkService

    init(networkService: NetworkService) {
        self.networkService = networkService
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        try await networkService.request(endpoint)
    }

    func requestData(_ endpoint: Endpoint) async throws -> Data {
        try await networkService.request(endpoint)
    }
}

// MARK: - Jellyfin API 服务实现（内部）
/// Jellyfin API 的具体实现（内部使用，不对外暴露）
class JellyfinAPIService {
    private let networkService: NetworkService

    init(networkService: NetworkService) {
        self.networkService = networkService
    }

    // MARK: - 认证
    func authenticate(username: String, password: String) async throws -> LoginResponse {
        let body: [String: Any] = [
            "Username": username,
            "Pw": password
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw NetworkError.invalidURL
        }

        let endpoint = APIEndpoint(
            path: APIConstants.Endpoints.authenticate,
            method: .post,
            body: bodyData,
            contentType: APIConstants.ContentType.json
        )

        return try await networkService.request(endpoint)
    }

    func logout() {
        // 由调用方处理状态清理
    }

    // MARK: - 媒体
    func fetchItems(userId: String, recursive: Bool, includeItemTypes: String) async throws -> [MediaItem] {
        let queryParams = [
            APIConstants.QueryParams.recursive: String(recursive),
            APIConstants.QueryParams.includeItemTypes: includeItemTypes
        ]

        let path = String(format: APIConstants.Endpoints.items, userId)
        let endpoint = APIEndpoint(
            path: path,
            method: .get,
            queryParams: queryParams
        )

        let response: JellyfinItemsResponse = try await networkService.request(endpoint)
        return response.items
    }

    // MARK: - 播放
    func buildPlaybackURL(itemId: String, apiKey: String) -> URL? {
        return networkService.urlBuilder.buildMediaURL(itemId: itemId, apiKey: apiKey)
    }
}
