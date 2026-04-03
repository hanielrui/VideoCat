import Foundation
import AVFoundation

/// 播放器复用池 - 使用 Actor 实现真正的线程安全
/// 可控池（类似连接池），安全复用，自动回收，无内存泄漏
actor PlayerPool {

    // MARK: - 单例
    static let shared = PlayerPool()

    // MARK: - 配置
    private let maxSize: Int = 3 // 最大复用数量
    
    // MARK: - 池（Actor 自动保护这些属性的访问）
    private var pool: [any Player] = []
    private var inUsePlayers: [ObjectIdentifier: any Player] = [:]



    // MARK: - 初始化
    private init() {
        // 预创建播放器
        Task {
            await preloadPlayers(count: 2)
        }
    }

    // MARK: - 公共接口

    /// 获取播放器（复用或新建）
    /// - Returns: 可用的播放器实例
    func acquirePlayer() async -> Player {
        // 优先复用已有播放器
        if let player = pool.popLast() {
            let id = ObjectIdentifier(player as AnyObject)
            inUsePlayers[id] = player
            Logger.debug("Reused player from pool, available: \(pool.count)")
            return player
        }

        // 创建新播放器
        let player = await MainActor.run {
            PlayerEngine()
        }
        let id = ObjectIdentifier(player as AnyObject)
        inUsePlayers[id] = player
        Logger.debug("Created new player, total in use: \(inUsePlayers.count)")
        return player
    }

    /// 获取播放器（返回 PlayerCore 保持向后兼容）
    /// - Returns: PlayerCore 实例
    /// - Note: 移除 @MainActor 注解，因为 actor 方法默认在 actor 执行上下文
    func acquirePlayerCore() async -> PlayerCore {
        // PlayerCore 内部使用 PlayerEngine，需要在主线程创建
        let playerCore = await MainActor.run {
            PlayerCore()
        }
        let id = ObjectIdentifier(playerCore as AnyObject)
        inUsePlayers[id] = playerCore
        return playerCore
    }

    /// 归还播放器到池中
    /// - Parameter player: 要归还的播放器
    func releasePlayer(_ player: Player) async {
        let id = ObjectIdentifier(player as AnyObject)

        // 检查是否在使用中
        guard inUsePlayers[id] != nil else { return }

        // 重置播放器状态
        await reset(player)

        // 如果池未满，加入可用池
        if pool.count < maxSize {
            pool.append(player)
            inUsePlayers.removeValue(forKey: id)
            Logger.debug("Player returned to pool, available: \(pool.count)")
        } else {
            // 池已满，彻底释放播放器
            await cleanupPlayer(player)
            inUsePlayers.removeValue(forKey: id)
            Logger.debug("Player released (pool full)")
        }
    }

    /// 归还播放器到池中（保持向后兼容）
    /// - Parameter player: 要归还的 PlayerCore
    func releasePlayer(_ player: PlayerCore) async {
        await releasePlayer(player as Player)
    }

    // MARK: - 私有方法

    /// 重置播放器状态
    private func reset(_ player: Player) async {
        await MainActor.run {
            player.stop()
            player.cleanup()
        }
    }

    /// 彻底清理播放器资源
    private func cleanupPlayer(_ player: Player) async {
        await MainActor.run {
            player.stop()
            player.cleanup()
        }
    }

    /// 预加载播放器
    private func preloadPlayers(count: Int) async {
        for _ in 0..<count {
            let player = await MainActor.run {
                PlayerEngine()
            }
            pool.append(player)
        }
        Logger.debug("Preloaded \(count) players")
    }

    // MARK: - 池管理

    /// 清空池（释放所有播放器）
    func clearPool() async {
        for player in pool {
            await cleanupPlayer(player)
        }
        pool.removeAll()

        for player in inUsePlayers.values {
            await cleanupPlayer(player)
        }
        inUsePlayers.removeAll()

        Logger.info("Player pool cleared")
    }

    /// 获取池状态
    var status: (available: Int, inUse: Int) {
        (pool.count, inUsePlayers.count)
    }

    /// 清理所有播放器资源（全量清理，如切后台）
    func removeAll() async {
        await clearPool()
    }
}

// MARK: - 播放器预加载器（Swift Concurrency）
actor PlayerPreloader {

    // MARK: - 属性
    private var preloadTasks: [String: AVAsset] = [:]
    private let maxPreloadCount: Int = 3

    // MARK: - 公共接口

    /// 预加载视频（Swift Concurrency）
    func preload(url: URL) async -> Bool {
        let key = url.absoluteString

        // 检查是否已有预加载任务
        if preloadTasks[key] != nil {
            return true
        }

        // 清理多余的预加载
        cleanupPreloadTasks()

        // 开始预加载
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        // 使用 async let 并行加载多个属性
        async let playableStatus = asset.load(.isPlayable)
        async let durationStatus = asset.load(.duration)
        async let tracksStatus = asset.load(.tracks)

        do {
            let (isPlayable, _, _) = try await (playableStatus, durationStatus, tracksStatus)

            if isPlayable {
                preloadTasks[key] = asset
                Logger.debug("Preloaded: \(url.lastPathComponent)")
                return true
            } else {
                Logger.warning("Asset not playable: \(url.lastPathComponent)")
                return false
            }
        } catch {
            Logger.warning("Failed to preload: \(error)")
            return false
        }
    }

    /// 预加载视频（带回调 - 保留向后兼容）
    func preload(url: URL, completion: ((Bool) -> Void)? = nil) {
        Task {
            let result = await preload(url: url)
            await MainActor.run {
                completion?(result)
            }
        }
    }

    /// 获取预加载的 Asset
    func getPreloadedAsset(for url: URL) -> AVAsset? {
        let key = url.absoluteString
        return preloadTasks[key]
    }

    /// 取消预加载
    func cancelPreload(for url: URL) {
        let key = url.absoluteString
        preloadTasks.removeValue(forKey: key)
    }

    /// 清除所有预加载
    func clearAll() {
        preloadTasks.removeAll()
        Logger.info("Preload cache cleared")
    }

    // MARK: - 私有方法

    private func cleanupPreloadTasks() {
        if preloadTasks.count >= maxPreloadCount {
            // 移除最旧的预加载
            if let firstKey = preloadTasks.keys.first {
                preloadTasks.removeValue(forKey: firstKey)
            }
        }
    }
}
