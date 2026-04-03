import Foundation

// MARK: - URL 构建器
class URLBuilder {

    private let baseURL: String

    init(baseURL: String) {
        self.baseURL = URLBuilder.normalize(baseURL)
    }

    // MARK: - URL 规范化
    static func normalize(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalized.isEmpty &&
            !normalized.hasPrefix("http://") &&
            !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }

        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }

        return normalized
    }

    // MARK: - 构建 URL
    func build(path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        // 确保 path 以 / 开头
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path

        var components = URLComponents(string: baseURL + normalizedPath)

        if let queryItems = queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            Logger.error("Failed to build URL: \(baseURL + normalizedPath)")
            throw NetworkError.invalidURL("Failed to build URL")
        }

        return url
    }

    // MARK: - 便捷方法
    func build(path: String, queryParams: [String: String]? = nil) throws -> URL {
        let queryItems = queryParams?.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try build(path: path, queryItems: queryItems)
    }

    // MARK: - 构建媒体播放 URL
    func buildMediaURL(itemId: String, apiKey: String) -> URL? {
        // 对 itemId 进行 URL 编码，防止特殊字符导致的问题
        let encodedItemId = itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemId

        let path = String(format: APIConstants.Endpoints.videoStream, encodedItemId)
        let queryItems = [
            URLQueryItem(name: APIConstants.QueryParams.apiKey, value: apiKey)
        ]

        do {
            return try build(path: path, queryItems: queryItems)
        } catch {
            Logger.error("Failed to build media URL: \(error)")
            return nil
        }
    }
}
