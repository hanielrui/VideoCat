import Foundation
import Combine
import UIKit
import AVFoundation

// MARK: - 缓存条目
struct CacheEntry: Codable {
    let key: String
    let type: CacheCategory
    let fileSize: Int64
    let createdAt: Date
    var lastAccessedAt: Date
    let metadata: [String: String]?
    
    var isExpired: Bool {
        // 由策略决定是否过期
        false
    }
}

// MARK: - 缓存类别
enum CacheCategory: String, Codable {
    case image
    case video
    case audio
    case data
    case network
    
    var defaultTTL: TimeInterval {
        switch self {
        case .image: return 7 * 24 * 60 * 60      // 7天
        case .video: return 7 * 24 * 60 * 60      // 7天
        case .audio: return 7 * 24 * 60 * 60      // 7天
        case .data: return 3 * 24 * 60 * 60       // 3天
        case .network: return 24 * 60 * 60       // 1天
        }
    }
}

// MARK: - CacheSystem 配置
struct CacheSystemConfig {
    // 内存缓存
    var memoryCountLimit: Int = 100
    var memoryCostLimit: Int = 50 * 1024 * 1024  // 50MB
    
    // 磁盘缓存
    var diskSizeLimit: Int64 = 500 * 1024 * 1024  // 500MB
    
    // TTL（秒），0 表示无限
    var ttlInterval: TimeInterval = 0
    
    // 策略
    var policy: CachePolicyType = .lruWithTTL
    
    // 自动清理间隔（秒）
    var autoCleanupInterval: TimeInterval = 3600
    
    // 清理阈值（超过此比例触发清理）
    var cleanupThreshold: Double = 0.9
    
    // 类别特定配置
    var categoryConfigs: [CacheCategory: CategoryConfig] = [:]
    
    struct CategoryConfig {
        var ttlInterval: TimeInterval?
        var diskSizeLimit: Int64?
        var memoryCountLimit: Int?
    }
    
    // 获取类别的 TTL
    func ttlInterval(for category: CacheCategory) -> TimeInterval {
        if let categoryConfig = categoryConfigs[category],
           let ttl = categoryConfig.ttlInterval {
            return ttl
        }
        return ttlInterval > 0 ? ttlInterval : category.defaultTTL
    }
    
    // 获取类别的磁盘限制
    func diskSizeLimit(for category: CacheCategory) -> Int64 {
        if let categoryConfig = categoryConfigs[category],
           let limit = categoryConfig.diskSizeLimit {
            return limit
        }
        return diskSizeLimit
    }
}

// MARK: - 缓存状态
enum CacheSystemState {
    case idle
    case loading
    case ready
    case cleaning
    case error(Error)
}

// MARK: - 缓存统计
struct CacheStatistics {
    var memoryItemCount: Int = 0
    var memorySize: Int64 = 0
    var diskItemCount: Int = 0
    var diskSize: Int64 = 0
    var hitCount: Int = 0
    var missCount: Int = 0
    var evictionCount: Int = 0
    
    var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0
    }
}

// MARK: - 存储协议
protocol CacheStorage {
    associatedtype Value
    
    func read(forKey key: String) -> Value?
    func write(_ value: Value, forKey key: String, cost: Int?)
    func remove(forKey key: String)
    func clear()
    func exists(forKey key: String) -> Bool
}

// MARK: - 缓存系统协议
/// 注意：Actor 协议方法默认是异步的，调用者需要使用 await
protocol CacheSystemProtocol {
    // 统一存储接口
    func get<T>(forKey key: String, category: CacheCategory) async -> T?
    func set<T>(_ value: T, forKey key: String, category: CacheCategory, cost: Int?) async
    func getData(forKey key: String, category: CacheCategory) async -> Data?
    func setData(_ data: Data, forKey key: String, category: CacheCategory) async
    func remove(forKey key: String, category: CacheCategory) async

    // 生命周期
    func clearMemory() async
    func clearDisk() async
    func clearAll() async

    // 状态
    func diskSize(for category: CacheCategory) async -> Int64
    var statistics: CacheStatistics { get }
    var statePublisher: AnyPublisher<CacheSystemState, Never> { get }

    // 配置
    func updateConfig(_ config: CacheSystemConfig) async
}

// MARK: - 统一缓存系统
/// 使用 Actor 提供真正的线程安全保证
/// 替代了之前的 class + DispatchQueue 模式
actor CacheSystem: CacheSystemProtocol {
    
    // MARK: - 单例
    static let shared = CacheSystem()
    
    // MARK: - 配置
    var config: CacheSystemConfig {
        didSet {
            applyConfig()
        }
    }
    
    // MARK: - 存储层
    private let memoryStorage: MemoryStorage
    private let diskStorage: DiskStorage
    
    // MARK: - 策略
    private var policy: CachePolicy!
    
    // MARK: - 状态（使用 nonisolated 存储以支持 Combine 发布）
    private var _state: CacheSystemState = .idle
    private var _statistics = CacheStatistics()
    
    /// 状态发布器 - nonisolated 允许从任何线程读取
    nonisolated var statePublisher: AnyPublisher<CacheSystemState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    private nonisolated let stateSubject = CurrentValueSubject<CacheSystemState, Never>(.idle)
    
    /// 统计发布器
    nonisolated var statisticsPublisher: AnyPublisher<CacheStatistics, Never> {
        statisticsSubject.eraseToAnyPublisher()
    }
    private nonisolated let statisticsSubject = CurrentValueSubject<CacheStatistics, Never>(CacheStatistics())
    
    // MARK: - 计算属性代理（保持向后兼容）
    nonisolated var statistics: CacheStatistics {
        statisticsSubject.value  // 这是安全的，因为 CurrentValueSubject 是线程安全的
    }
    
    // MARK: - 清理任务
    private var cleanupTask: Task<Void, Never>?
    private var isCleanupScheduled = false
    
    // MARK: - 初始化
    private init(config: CacheSystemConfig = CacheSystemConfig()) {
        self.config = config
        self.memoryStorage = MemoryStorage()
        self.diskStorage = DiskStorage()
        
        // 初始化策略
        self.policy = CachePolicyFactory.create(policy: config.policy, config: config)
        
        applyConfig()
        startLifecycle()
    }
    
    // MARK: - 统一存储接口
    func get<T>(forKey key: String, category: CacheCategory) -> T? {
        let compositeKey = makeKey(key, category: category)
        
        // 1. 内存缓存优先
        if let value = memoryStorage.object(forKey: compositeKey) as? T {
            recordHit()
            updateAccessTime(compositeKey, category: category)
            return value
        }
        
        // 2. 磁盘缓存
        if let data = diskStorage.readData(forKey: compositeKey, category: category) {
            // 回填内存
            if let value = convertFromData(data, type: T.self) {
                memoryStorage.set(value, forKey: compositeKey, cost: data.count)
                recordHit()
                updateAccessTime(compositeKey, category: category)
                return value
            }
        }
        
        recordMiss()
        return nil
    }
    
    func set<T>(_ value: T, forKey key: String, category: CacheCategory, cost: Int?) {
        let compositeKey = makeKey(key, category: category)

        // 内存缓存（受 cost 参数控制）
        memoryStorage.set(value as AnyObject, forKey: compositeKey, cost: cost)

        // 异步写入磁盘（Data 类型）- 使用 Task 避免阻塞 actor
        // 注意：磁盘存储不受 cost 参数影响，成本仅应用于内存缓存
        // 如果快速连续写入同一 key，磁盘写入是异步的，可能存在竞态条件
        if let data = convertToData(value) {
            Task {
                diskStorage.writeData(data, forKey: compositeKey, category: category)
                await scheduleCleanupIfNeeded()
            }
        }
    }
    

    
    func getData(forKey key: String, category: CacheCategory) -> Data? {
        let compositeKey = makeKey(key, category: category)
        
        // 1. 内存缓存优先
        if let data = memoryStorage.data(forKey: compositeKey) {
            recordHit()
            updateAccessTime(compositeKey, category: category)
            return data
        }
        
        // 2. 磁盘缓存
        if let data = diskStorage.readData(forKey: compositeKey, category: category) {
            // 回填内存
            memoryStorage.setData(data, forKey: compositeKey)
            recordHit()
            updateAccessTime(compositeKey, category: category)
            return data
        }
        
        recordMiss()
        return nil
    }
    
    func setData(_ data: Data, forKey key: String, category: CacheCategory) {
        let compositeKey = makeKey(key, category: category)
        
        // 内存缓存
        memoryStorage.setData(data, forKey: compositeKey)
        
        // 异步写入磁盘 - 使用 Task 避免阻塞 actor
        Task {
            diskStorage.writeData(data, forKey: compositeKey, category: category)
            await scheduleCleanupIfNeeded()
        }
    }
    
    func remove(forKey key: String, category: CacheCategory) {
        let compositeKey = makeKey(key, category: category)
        memoryStorage.remove(forKey: compositeKey)
        diskStorage.remove(forKey: compositeKey, category: category)
    }
    
    // MARK: - 生命周期
    func clearMemory() {
        memoryStorage.clear()
        _statistics.memoryItemCount = 0
        _statistics.memorySize = 0
        publishStatistics()
        Logger.info("[CacheSystem] Memory cache cleared")
    }
    
    func clearDisk() {
        diskStorage.clear()
        _statistics.diskItemCount = 0
        _statistics.diskSize = 0
        publishStatistics()
        Logger.info("[CacheSystem] Disk cache cleared")
    }
    
    func clearAll() {
        clearMemory()
        clearDisk()
        _statistics = CacheStatistics()
        publishStatistics()
    }
    
    // MARK: - 状态查询
    func diskSize(for category: CacheCategory) -> Int64 {
        diskStorage.totalSize(for: category)
    }
    
    func updateConfig(_ config: CacheSystemConfig) {
        self.config = config
    }
    
    // MARK: - 私有方法
    
    private func makeKey(_ key: String, category: CacheCategory) -> String {
        "\(category.rawValue)_\(key)"
    }
    
    private func applyConfig() {
        // 应用内存配置
        memoryStorage.countLimit = config.memoryCountLimit
        memoryStorage.totalCostLimit = config.memoryCostLimit
        
        // 重建策略
        policy = CachePolicyFactory.create(policy: config.policy, config: config)
        
        Logger.info("[CacheSystem] Config applied: \(config.policy.rawValue), disk: \(config.diskSizeLimit)")
    }
    
    private func startLifecycle() {
        _state = .loading
        stateSubject.send(.loading)
        
        // 加载磁盘索引
        Task {
            diskStorage.loadIndex()
            
            _state = .ready
            stateSubject.send(.ready)
            schedulePeriodicCleanup()
        }
    }
    
    // MARK: - 统计
    
    private func recordHit() {
        _statistics.hitCount += 1
        publishStatistics()
    }
    
    private func recordMiss() {
        _statistics.missCount += 1
        publishStatistics()
    }
    
    private func publishStatistics() {
        statisticsSubject.send(_statistics)
    }
    
    private func updateAccessTime(_ key: String, category: CacheCategory) {
        diskStorage.updateAccessTime(forKey: key, category: category)
    }
    
    // MARK: - 清理逻辑
    
    private func scheduleCleanupIfNeeded() {
        guard !isCleanupScheduled else { return }
        isCleanupScheduled = true
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒延迟
            isCleanupScheduled = false
            await performCleanupIfNeeded()
        }
    }
    
    private func schedulePeriodicCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.config.autoCleanupInterval else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                await self?.performCleanupIfNeeded()
            }
        }
    }
    
    private func performCleanupIfNeeded() {
        let currentSize = diskStorage.totalSize()
        let limit = config.diskSizeLimit
        
        guard currentSize > Int64(Double(limit) * config.cleanupThreshold) else {
            return
        }
        
        _state = .cleaning
        stateSubject.send(.cleaning)
        
        // 执行过期清理
        diskStorage.removeExpired(ttlInterval: config.ttlInterval)
        
        // 如果仍然超过限制，执行 LRU 淘汰
        let newSize = diskStorage.totalSize()
        if newSize > limit {
            let targetSize = Int64(Double(limit) * 0.8)
            diskStorage.evictLRU(policy: policy, targetSize: targetSize, config: config)
        }
        
        _state = .ready
        stateSubject.send(.ready)
        Logger.debug("[CacheSystem] Cleanup completed, current size: \(diskStorage.totalSize())")
    }
    
    // MARK: - 数据转换
    
    private func convertToData<T>(_ value: T) -> Data? {
        if let data = value as? Data {
            return data
        }
        if let string = value as? String {
            return string.data(using: .utf8)
        }
        return try? JSONEncoder().encode(value)
    }
    
    private func convertFromData<T>(_ data: Data, type: T.Type) -> T? {
        if type == Data.self {
            return data as? T
        }
        if type == String.self {
            return String(data: data, encoding: .utf8) as? T
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - 内存存储
final class MemoryStorage {
    var countLimit: Int = 100
    var totalCostLimit: Int = 50 * 1024 * 1024
    
    private let cache = NSCache<NSString, AnyObject>()
    private var dataCache = NSCache<NSString, NSData>()
    
    init() {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }
    
    func object<T>(forKey key: String) -> T? {
        cache.object(forKey: key as NSString) as? T
    }
    
    func data(forKey key: String) -> Data? {
        dataCache.object(forKey: key as NSString) as Data?
    }
    
    func set(_ value: AnyObject, forKey key: String, cost: Int?) {
        cache.setObject(value, forKey: key as NSString, cost: cost ?? 0)
    }
    
    func setData(_ data: Data, forKey key: String) {
        dataCache.setObject(data as NSData, forKey: key as NSString)
    }
    
    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
        dataCache.removeObject(forKey: key as NSString)
    }
    
    func clear() {
        cache.removeAllObjects()
        dataCache.removeAllObjects()
    }
}

// MARK: - 磁盘存储
final class DiskStorage {
    private let storageURL: URL
    private let fileManager = FileManager.default
    private var index: [String: CacheEntry] = [:]
    private let indexQueue = DispatchQueue(label: "com.cachesystem.disk.index", qos: .utility)
    
    init() {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            storageURL = URL(fileURLWithPath: "/tmp/CacheSystem")
            try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
            return
        }
        storageURL = caches.appendingPathComponent("CacheSystem")
        try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }
    
    // MARK: - 读写
    
    func readData(forKey key: String, category: CacheCategory) -> Data? {
        let fileURL = fileURL(for: key, category: category)
        return try? Data(contentsOf: fileURL)
    }
    
    func writeData(_ data: Data, forKey key: String, category: CacheCategory) {
        let fileURL = fileURL(for: key, category: category)
        
        do {
            try data.write(to: fileURL)
            
            let entry = CacheEntry(
                key: key,
                type: category,
                fileSize: Int64(data.count),
                createdAt: Date(),
                lastAccessedAt: Date(),
                metadata: nil
            )
            
            indexQueue.async { [weak self] in
                self?.index[key] = entry
                self?.saveIndex()
            }
        } catch {
            Logger.error("[DiskStorage] Write failed: \(error)")
        }
    }
    
    func remove(forKey key: String, category: CacheCategory) {
        let fileURL = fileURL(for: key, category: category)
        try? fileManager.removeItem(at: fileURL)
        
        indexQueue.async { [weak self] in
            self?.index.removeValue(forKey: key)
            self?.saveIndex()
        }
    }
    
    func clear() {
        try? fileManager.removeItem(at: storageURL)
        try? fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        
        indexQueue.async { [weak self] in
            self?.index.removeAll()
            self?.saveIndex()
        }
    }
    
    func exists(forKey key: String, category: CacheCategory) -> Bool {
        let fileURL = fileURL(for: key, category: category)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - 索引
    
    func totalSize(for category: CacheCategory) -> Int64 {
        indexQueue.sync {
            index.values
                .filter { $0.type == category }
                .reduce(0) { $0 + $1.fileSize }
        }
    }
    
    func totalSize() -> Int64 {
        indexQueue.sync {
            index.values.reduce(0) { $0 + $1.fileSize }
        }
    }
    
    func itemCount(for category: CacheCategory) -> Int {
        indexQueue.sync {
            index.values.filter { $0.type == category }.count
        }
    }
    
    func updateAccessTime(forKey key: String, category: CacheCategory) {
        indexQueue.async { [weak self] in
            guard var entry = self?.index[key] else { return }
            entry = CacheEntry(
                key: entry.key,
                type: entry.type,
                fileSize: entry.fileSize,
                createdAt: entry.createdAt,
                lastAccessedAt: Date(),
                metadata: entry.metadata
            )
            self?.index[key] = entry
            self?.saveIndex()
        }
    }
    
    func removeExpired(ttlInterval: TimeInterval) {
        indexQueue.async { [weak self] in
            guard let self = self, ttlInterval > 0 else { return }
            
            let now = Date()
            let expiredKeys = self.index.filter { _, entry in
                let expiration = entry.createdAt.addingTimeInterval(ttlInterval)
                return now > expiration
            }.map { $0.key }
            
            for key in expiredKeys {
                if let entry = self.index[key] {
                    let fileURL = self.fileURL(for: entry.key, category: entry.type)
                    try? self.fileManager.removeItem(at: fileURL)
                    self.index.removeValue(forKey: key)
                }
            }
            
            if !expiredKeys.isEmpty {
                self.saveIndex()
                Logger.debug("[DiskStorage] Removed \(expiredKeys.count) expired entries")
            }
        }
    }
    
    func evictLRU(policy: CachePolicy, targetSize: Int64, config: CacheSystemConfig) {
        indexQueue.async { [weak self] in
            guard let self = self else { return }
            
            let currentSize = self.index.values.reduce(0) { $0 + $1.fileSize }
            guard currentSize > targetSize else { return }
            
            let targets = policy.selectEvictionTargets(
                entries: self.index,
                currentSize: currentSize,
                targetSize: targetSize,
                config: config
            )
            
            for key in targets {
                if let entry = self.index[key] {
                    let fileURL = self.fileURL(for: entry.key, category: entry.type)
                    try? self.fileManager.removeItem(at: fileURL)
                    self.index.removeValue(forKey: key)
                }
            }
            
            self.saveIndex()
            Logger.debug("[DiskStorage] Evicted \(targets.count) entries")
        }
    }
    
    // MARK: - 持久化
    
    func loadIndex() {
        let indexURL = storageURL.appendingPathComponent("index.json")
        
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([CacheEntry].self, from: data) else {
            return
        }
        
        for entry in entries {
            // 只加载仍然存在的文件
            if exists(forKey: entry.key, category: entry.type) {
                index[entry.key] = entry
            }
        }
    }
    
    private func saveIndex() {
        let indexURL = storageURL.appendingPathComponent("index.json")
        
        do {
            let data = try JSONEncoder().encode(Array(index.values))
            try data.write(to: indexURL)
        } catch {
            Logger.error("[DiskStorage] Save index failed: \(error)")
        }
    }
    
    // MARK: - 工具
    
    private func fileURL(for key: String, category: CacheCategory) -> URL {
        let sanitized = key.sanitizedFileName
        return storageURL.appendingPathComponent("\(category.rawValue)_\(sanitized)")
    }
}

// MARK: - 字符串扩展
private extension String {
    var sanitizedFileName: String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return self.components(separatedBy: invalid).joined().prefix(100).description
    }
}

// MARK: - 图片缓存扩展
/// 直接使用 CacheSystem 的图片缓存功能
extension CacheSystem {

    /// 获取图片
    func image(for key: String) -> UIImage? {
        // 先从内存缓存获取
        if let cached: UIImage = get(forKey: key, category: .image) {
            return cached
        }

        // 从数据加载
        if let data = getData(forKey: key, category: .image),
           let image = UIImage(data: data) {
            // 回填内存缓存
            set(image, forKey: key, category: .image, cost: data.count)
            return image
        }

        return nil
    }

    /// 存储图片
    func setImage(_ image: UIImage, for key: String) {
        // 内存缓存
        set(image, forKey: key, category: .image, cost: nil)

        // 磁盘缓存（异步）- 由于已经在 actor 中，使用 Task
        Task {
            let data: Data?
            if image.hasAlpha {
                data = image.pngData()
            } else {
                data = image.jpegData(compressionQuality: 0.8)
            }

            if let imageData = data {
                setData(imageData, forKey: key, category: .image)
            }
        }
    }

    /// 移除图片
    func removeImage(for key: String) {
        remove(forKey: key, category: .image)
    }

    /// 异步加载图片（Swift Concurrency）
    func loadImage(from url: URL) async -> UIImage? {
        let key = url.absoluteString

        // 同步检查缓存
        if let cached = image(for: key) {
            return cached
        }

        // 异步下载
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return nil
            }

            // 缓存
            setImage(image, for: key)

            return image
        } catch {
            Logger.error("Failed to load image: \(error)")
            return nil
        }
    }
}

// MARK: - 视频缓存扩展
/// 直接使用 CacheSystem 的视频缓存功能
extension CacheSystem {

    /// 内存缓存（直接缓存 AVURLAsset）
    /// 配置限制以防止内存溢出
    private static let assetMemoryCache: NSCache<NSString, AVURLAsset> = {
        let cache = NSCache<NSString, AVURLAsset>()
        cache.countLimit = 10           // 最多缓存 10 个 Asset
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB 内存限制
        return cache
    }()

    /// 获取缓存的 Asset（内存缓存优先）
    func cachedAsset(for url: URL) -> AVURLAsset? {
        let key = cacheKey(for: url)

        // 1. 内存缓存
        if let asset = Self.assetMemoryCache.object(forKey: key as NSString) {
            Logger.debug("Memory cache hit: \(url.lastPathComponent)")
            return asset
        }

        // 2. 磁盘缓存
        if let fileURL = cachedFileURL(for: url) {
            let asset = AVURLAsset(url: fileURL)

            // 回填内存缓存
            Self.assetMemoryCache.setObject(asset, forKey: key as NSString)

            Logger.debug("Disk cache hit: \(url.lastPathComponent)")
            return asset
        }

        return nil
    }

    /// 缓存 Asset 到内存
    func cacheAsset(_ asset: AVAsset, for url: URL) {
        guard let urlAsset = asset as? AVURLAsset else {
            Logger.warning("Cannot cache non-URL asset: \(url.lastPathComponent)")
            return
        }

        let key = cacheKey(for: url)
        Self.assetMemoryCache.setObject(urlAsset, forKey: key as NSString)
        Logger.debug("Cached asset to memory: \(url.lastPathComponent)")
    }

    /// 缓存视频到磁盘（Swift Concurrency）
    func cacheVideo(from sourceURL: URL) async -> Bool {
        let key = cacheKey(for: sourceURL)

        // 检查是否已缓存
        if cachedFileURL(for: sourceURL) != nil {
            return true
        }

        do {
            // 异步下载
            let (tempURL, _) = try await URLSession.shared.download(from: sourceURL)

            // 读取临时文件数据并写入缓存
            let data = try Data(contentsOf: tempURL)
            setData(data, forKey: key, category: .video)

            Logger.info("Cached to disk: \(sourceURL.lastPathComponent), size: \(data.count)")
            return true
        } catch {
            Logger.error("Failed to cache video: \(error)")
            return false
        }
    }

    /// 清除视频内存缓存
    func clearVideoMemoryCache() {
        Self.assetMemoryCache.removeAllObjects()
    }

    /// 获取当前视频缓存大小
    func videoCacheSize() -> Int64 {
        diskSize(for: .video)
    }

    // MARK: - 私有方法
    private nonisolated func cacheKey(for url: URL) -> String {
        url.absoluteString.data(using: .utf8)?.base64EncodedString() ?? url.lastPathComponent
    }

    private nonisolated func cachedFileURL(for url: URL) -> URL? {
        let key = cacheKey(for: url)

        // 返回缓存数据的临时文件路径
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let storageURL = caches.appendingPathComponent("CacheSystem")
        let sanitizedKey = key.data(using: .utf8)?.base64EncodedString() ?? key
        let fileURL = storageURL.appendingPathComponent("video_\(sanitizedKey.prefix(100))")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        return nil
    }
}
