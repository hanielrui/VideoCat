import Foundation
import UIKit

// MARK: - ImageCache 协议
/// 图片缓存协议，支持依赖注入和单元测试
protocol ImageCacheProtocol: AnyObject {
    /// 获取图片
    func get(for key: String) async -> UIImage?

    /// 存储图片
    func set(_ image: UIImage, for key: String) async

    /// 移除图片
    func remove(for key: String) async

    /// 异步加载图片
    func load(from url: URL) async -> UIImage?

    /// 清除内存缓存
    func clearMemoryCache() async

    /// 清除所有缓存
    func clearAll() async
}

// MARK: - ImageCache 实现
/// 图片缓存管理器 - 直接代理到 CacheSystem 扩展
/// 保留协议接口用于依赖注入
final class ImageCache: ImageCacheProtocol {

    // MARK: - 单例
    static let shared = ImageCache()

    // MARK: - 依赖
    private let cacheSystem: CacheSystem

    // MARK: - 初始化
    private init(cacheSystem: CacheSystem = .shared) {
        self.cacheSystem = cacheSystem
    }

    // MARK: - ImageCacheProtocol 实现（代理到 CacheSystem）

    func get(for key: String) -> UIImage? {
        cacheSystem.image(for: key)
    }

    func set(_ image: UIImage, for key: String) {
        cacheSystem.setImage(image, for: key)
    }

    func remove(for key: String) {
        cacheSystem.removeImage(for: key)
    }

    func load(from url: URL) async -> UIImage? {
        await cacheSystem.loadImage(from: url)
    }

    func clearMemoryCache() {
        cacheSystem.clearMemory()
    }

    func clearAll() {
        cacheSystem.clearAll()
    }
}

// MARK: - UIImageView 扩展
extension UIImageView {

    private static var imageCacheKey = "imageCacheKey"
    private static var customImageCacheKey = "customImageCacheKey"

    /// 自定义图片缓存实例（通过依赖注入设置）
    private var injectedImageCache: ImageCacheProtocol? {
        get { objc_getAssociatedObject(self, &UIImageView.customImageCacheKey) as? ImageCacheProtocol }
        set { objc_setAssociatedObject(self, &UIImageView.customImageCacheKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var imageTask: Task<Void, Never>? {
        get { objc_getAssociatedObject(self, &UIImageView.imageCacheKey) as? Task<Void, Never> }
        set { objc_setAssociatedObject(self, &UIImageView.imageCacheKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 设置自定义图片缓存（用于依赖注入）
    func setImageCache(_ cache: ImageCacheProtocol?) {
        injectedImageCache = cache
    }

    /// 异步加载图片（带缓存 - Swift Concurrency）
    /// 使用注入的缓存或默认单例
    func setImage(from url: URL?, placeholder: UIImage? = nil) {
        // 显示占位图
        image = placeholder

        guard let url = url else { return }

        let key = url.absoluteString
        let cache = injectedImageCache ?? ImageCache.shared

        // 异步加载
        imageTask?.cancel()

        // 异步加载
        imageTask = Task { [weak self] in
            // 检查缓存
            if let cached = await cache.get(for: key) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.image = cached
                }
                return
            }

            let loadedImage = await cache.load(from: url)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.image = loadedImage
            }
        }
    }

    /// 取消加载
    func cancelImageLoad() {
        imageTask?.cancel()
        imageTask = nil
    }
}
