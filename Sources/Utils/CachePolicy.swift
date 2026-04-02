import Foundation

// MARK: - 缓存策略协议
protocol CachePolicy: AnyObject {
    /// 策略名称
    var name: String { get }
    
    /// 是否应该淘汰条目
    func shouldEvict(entry: CacheEntry, currentSize: Int64, config: CacheSystemConfig) -> Bool
    
    /// 选择要淘汰的条目（返回要淘汰的 key）
    func selectEvictionTargets(
        entries: [String: CacheEntry],
        currentSize: Int64,
        targetSize: Int64,
        config: CacheSystemConfig
    ) -> [String]
}

// MARK: - LRU 策略（最近最少使用）
final class LRUCachePolicy: CachePolicy {
    let name = "LRU"
    
    func shouldEvict(entry: CacheEntry, currentSize: Int64, config: CacheSystemConfig) -> Bool {
        // 超过大小限制时淘汰
        if config.diskSizeLimit > 0 && currentSize > config.diskSizeLimit {
            return true
        }
        
        // 检查 TTL
        if config.ttlInterval > 0 {
            let expirationDate = entry.createdAt.addingTimeInterval(config.ttlInterval)
            if Date() > expirationDate {
                return true
            }
        }
        
        return false
    }
    
    func selectEvictionTargets(
        entries: [String: CacheEntry],
        currentSize: Int64,
        targetSize: Int64,
        config: CacheSystemConfig
    ) -> [String] {
        let sortedEntries = entries.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }
        
        var targets: [String] = []
        var freedSize: Int64 = 0
        
        for (key, entry) in sortedEntries {
            if currentSize - freedSize <= targetSize {
                break
            }
            targets.append(key)
            freedSize += entry.fileSize
        }
        
        return targets
    }
}

// MARK: - LFU 策略（最不经常使用）
final class LFUCachePolicy: CachePolicy {
    let name = "LFU"
    
    // 访问频率计数器
    private var accessCount: [String: Int] = [:]
    
    func shouldEvict(entry: CacheEntry, currentSize: Int64, config: CacheSystemConfig) -> Bool {
        if config.diskSizeLimit > 0 && currentSize > config.diskSizeLimit {
            return true
        }
        
        if config.ttlInterval > 0 {
            let expirationDate = entry.createdAt.addingTimeInterval(config.ttlInterval)
            if Date() > expirationDate {
                return true
            }
        }
        
        return false
    }
    
    func selectEvictionTargets(
        entries: [String: CacheEntry],
        currentSize: Int64,
        targetSize: Int64,
        config: CacheSystemConfig
    ) -> [String] {
        // 按访问频率排序（升序）
        let sortedEntries = entries.sorted { entry1, entry2 in
            let count1 = accessCount[entry1.key] ?? 0
            let count2 = accessCount[entry2.key] ?? 0
            return count1 < count2
        }
        
        var targets: [String] = []
        var freedSize: Int64 = 0
        
        for (key, entry) in sortedEntries {
            if currentSize - freedSize <= targetSize {
                break
            }
            targets.append(key)
            freedSize += entry.fileSize
        }
        
        return targets
    }
    
    func recordAccess(for key: String) {
        accessCount[key, default: 0] += 1
    }
}

// MARK: - FIFO 策略（先进先出）
final class FIFOCachePolicy: CachePolicy {
    let name = "FIFO"
    
    func shouldEvict(entry: CacheEntry, currentSize: Int64, config: CacheSystemConfig) -> Bool {
        if config.diskSizeLimit > 0 && currentSize > config.diskSizeLimit {
            return true
        }
        
        if config.ttlInterval > 0 {
            let expirationDate = entry.createdAt.addingTimeInterval(config.ttlInterval)
            if Date() > expirationDate {
                return true
            }
        }
        
        return false
    }
    
    func selectEvictionTargets(
        entries: [String: CacheEntry],
        currentSize: Int64,
        targetSize: Int64,
        config: CacheSystemConfig
    ) -> [String] {
        // 按创建时间排序（升序）
        let sortedEntries = entries.sorted { $0.value.createdAt < $1.value.createdAt }
        
        var targets: [String] = []
        var freedSize: Int64 = 0
        
        for (key, entry) in sortedEntries {
            if currentSize - freedSize <= targetSize {
                break
            }
            targets.append(key)
            freedSize += entry.fileSize
        }
        
        return targets
    }
}

// MARK: - TTL 策略（仅基于过期时间）
final class TTLCachePolicy: CachePolicy {
    let name = "TTL"
    
    func shouldEvict(entry: CacheEntry, currentSize: Int64, config: CacheSystemConfig) -> Bool {
        // TTL 策略下，只要过期就淘汰
        if config.ttlInterval > 0 {
            let expirationDate = entry.createdAt.addingTimeInterval(config.ttlInterval)
            return Date() > expirationDate
        }
        
        return false
    }
    
    func selectEvictionTargets(
        entries: [String: CacheEntry],
        currentSize: Int64,
        targetSize: Int64,
        config: CacheSystemConfig
    ) -> [String] {
        // 只返回过期的条目
        guard config.ttlInterval > 0 else { return [] }
        
        let now = Date()
        return entries.filter { _, entry in
            let expirationDate = entry.createdAt.addingTimeInterval(config.ttlInterval)
            return now > expirationDate
        }.map { $0.key }
    }
}

// MARK: - 复合策略（支持多条件）
final class CompositeCachePolicy: CachePolicy {
    let name: String
    private let policies: [CachePolicy]
    
    init(policies: [CachePolicy]) {
        self.name = policies.map { $0.name }.joined(separator: "+")
        self.policies = policies
    }
    
    func shouldEvict(entry: CacheEntry, currentSize: Int64, config: CacheSystemConfig) -> Bool {
        policies.contains { $0.shouldEvict(entry: entry, currentSize: currentSize, config: config) }
    }
    
    func selectEvictionTargets(
        entries: [String: CacheEntry],
        currentSize: Int64,
        targetSize: Int64,
        config: CacheSystemConfig
    ) -> [String] {
        var allTargets = Set<String>()
        
        for policy in policies {
            let targets = policy.selectEvictionTargets(
                entries: entries,
                currentSize: currentSize,
                targetSize: targetSize,
                config: config
            )
            allTargets.formUnion(targets)
        }
        
        return Array(allTargets)
    }
}

// MARK: - 策略工厂
enum CachePolicyFactory {
    static func create(policy: CachePolicyType, config: CacheSystemConfig) -> CachePolicy {
        switch policy {
        case .lru:
            return LRUCachePolicy()
        case .lfu:
            return LFUCachePolicy()
        case .fifo:
            return FIFOCachePolicy()
        case .ttl:
            return TTLCachePolicy()
        case .lruWithTTL:
            return CompositeCachePolicy(policies: [LRUCachePolicy(), TTLCachePolicy()])
        }
    }
}

// MARK: - 策略类型枚举
enum CachePolicyType: String, Codable {
    case lru
    case lfu
    case fifo
    case ttl
    case lruWithTTL
}
