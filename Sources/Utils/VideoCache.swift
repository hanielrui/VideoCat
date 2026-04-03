import Foundation
import AVFoundation

/// 视频缓存管理器 - 直接代理到 CacheSystem 扩展
final class VideoCache {

    // MARK: - 单例
    static let shared = VideoCache()

    // MARK: - 依赖
    private let cacheSystem: CacheSystem

    // MARK: - 初始化
    private init(cacheSystem: CacheSystem = .shared) {
        self.cacheSystem = cacheSystem
    }

    // MARK: - 公共接口（代理到 CacheSystem 扩展）

    /// 获取缓存的 Asset（内存缓存优先）
    func getCachedAsset(for url: URL) async -> AVURLAsset? {
        await cacheSystem.cachedAsset(for: url)
    }

    /// 缓存 Asset 到内存
    func cacheToMemory(_ asset: AVAsset, for url: URL) async {
        await cacheSystem.cacheAsset(asset, for: url)
    }

    /// 缓存视频到磁盘（Swift Concurrency）
    func cacheToDisk(from sourceURL: URL) async -> Bool {
        await cacheSystem.cacheVideo(from: sourceURL)
    }

    /// 缓存视频到磁盘（带回调 - 保留向后兼容）
    func cacheToDisk(from sourceURL: URL, completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            let result = await self?.cacheToDisk(from: sourceURL) ?? false
            await MainActor.run {
                completion(result)
            }
        }
    }

    /// 清除所有缓存
    func clearCache() async {
        await cacheSystem.clearVideoMemoryCache()
        await cacheSystem.clearAll()
        Logger.info("Video cache cleared")
    }

    /// 获取当前缓存大小
    func getCurrentCacheSize() async -> Int64 {
        await cacheSystem.videoCacheSize()
    }
}