import Foundation
import UIKit
import Combine

// MARK: - 缓存类型（保留兼容）
enum CacheType: String {
    case image
    case video
    case data
}

// MARK: - 缓存配置（保留兼容）
struct CacheConfig {
    var memoryCountLimit: Int = 100
    var memoryCostLimit: Int = 50 * 1024 * 1024 // 50MB
    var diskSizeLimit: Int64 = 200 * 1024 * 1024 // 200MB

    var expirationDaysMap: [CacheType: Int] = [
        .image: 7,
        .video: 7,
        .data: 3
    ]

    func expirationDays(for type: CacheType) -> Int? {
        expirationDaysMap[type]
    }
}

// MARK: - 缓存服务协议
/// 统一缓存服务接口
protocol CacheService {
    func get<T: AnyObject>(forKey key: String, type: CacheType) async -> T?
    func set<T: AnyObject>(_ value: T, forKey key: String, type: CacheType, cost: Int?) async

    func getData(forKey key: String, type: CacheType) async -> Data?
    func setData(_ data: Data, forKey key: String, type: CacheType) async

    func remove(forKey key: String, type: CacheType) async
    func clearMemory() async
    func clearDisk() async
    func clearAll() async

    func diskSize() async -> Int64
}

// MARK: - 统一缓存管理器
/// 适配器模式：兼容旧接口，直接代理到 CacheSystem
final class CacheManager: CacheService {

    // MARK: - 单例
    static let shared = CacheManager()

    // MARK: - 配置（保留兼容）
    static var config = CacheConfig()

    // MARK: - 兼容映射
    private static let categoryMapping: [CacheType: CacheCategory] = [
        .image: .image,
        .video: .video,
        .data: .data
    ]

    // MARK: - 初始化
    private init() {
        syncConfigToSystem()
    }

    // MARK: - 配置同步
    private static func syncConfigToSystem() {
        var systemConfig = CacheSystemConfig()
        systemConfig.memoryCountLimit = CacheManager.config.memoryCountLimit
        systemConfig.memoryCostLimit = CacheManager.config.memoryCostLimit
        systemConfig.diskSizeLimit = CacheManager.config.diskSizeLimit
        systemConfig.policy = .lruWithTTL

        // 映射 TTL
        systemConfig.categoryConfigs = [
            .image: .init(ttlInterval: TimeInterval(CacheConfig().expirationDaysMap[.image] ?? 7) * 24 * 60 * 60),
            .video: .init(ttlInterval: TimeInterval(CacheConfig().expirationDaysMap[.video] ?? 7) * 24 * 60 * 60),
            .data: .init(ttlInterval: TimeInterval(CacheConfig().expirationDaysMap[.data] ?? 3) * 24 * 60 * 60)
        ]

        Task {
            await CacheSystem.shared.updateConfig(systemConfig)
        }
    }

    // MARK: - CacheService 实现（直接代理到 CacheSystem）

    func get<T: AnyObject>(forKey key: String, type: CacheType) async -> T? {
        guard let category = Self.categoryMapping[type] else { return nil }
        return await CacheSystem.shared.get(forKey: key, category: category)
    }

    func set<T: AnyObject>(_ value: T, forKey key: String, type: CacheType, cost: Int?) async {
        guard let category = Self.categoryMapping[type] else { return }
        await CacheSystem.shared.set(value, forKey: key, category: category, cost: cost)
    }

    func getData(forKey key: String, type: CacheType) async -> Data? {
        guard let category = Self.categoryMapping[type] else { return nil }
        return await CacheSystem.shared.getData(forKey: key, category: category)
    }

    func setData(_ data: Data, forKey key: String, type: CacheType) async {
        guard let category = Self.categoryMapping[type] else { return }
        await CacheSystem.shared.setData(data, forKey: key, category: category)
    }

    func remove(forKey key: String, type: CacheType) async {
        guard let category = Self.categoryMapping[type] else { return }
        await CacheSystem.shared.remove(forKey: key, category: category)
    }

    func clearMemory() async {
        await CacheSystem.shared.clearMemory()
    }

    func clearDisk() async {
        await CacheSystem.shared.clearDisk()
    }

    func clearAll() async {
        await CacheSystem.shared.clearAll()
    }

    func diskSize() async -> Int64 {
        return await CacheSystem.shared.diskSize(for: .data)
    }

    // MARK: - 便捷属性（直接代理到 CacheSystem）

    /// 获取 CacheSystem 实例
    static var system: CacheSystem { CacheSystem.shared }

    /// 更新配置
    func updateConfig(_ config: CacheConfig) {
        CacheManager.config = config
        Self.syncConfigToSystem()
    }

    /// 获取统计信息
    var statistics: CacheStatistics {
        CacheSystem.shared.statistics
    }

    /// 状态发布者
    var statePublisher: AnyPublisher<CacheSystemState, Never> {
        CacheSystem.shared.statePublisher
    }
}