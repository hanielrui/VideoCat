import Foundation
import Network

// MARK: - NetworkMonitor 协议
/// 网络监控协议，支持依赖注入和单元测试
protocol NetworkMonitorProtocol: AnyObject {
    /// 是否已连接
    var isConnected: Bool { get }

    /// 连接类型
    var connectionType: NetworkMonitor.ConnectionType { get }

    /// 状态变化回调
    var onStatusChange: ((Bool) -> Void)? { get set }

    /// 开始监控
    func start()

    /// 停止监控
    func stop()
}

// MARK: - NetworkMonitor 实现
/// 网络状态监控
final class NetworkMonitor: NetworkMonitorProtocol {

    // MARK: - 单例（保留向后兼容）
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    var onStatusChange: ((Bool) -> Void)?

    private init() {
        start()
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            self.isConnected = path.status == .satisfied

            if path.usesInterfaceType(.wifi) {
                self.connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                self.connectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                self.connectionType = .ethernet
            } else {
                self.connectionType = .unknown
            }

            // 确保回调在主线程执行，因为通常会更新 UI
            DispatchQueue.main.async {
                self.onStatusChange?(self.isConnected)
            }
            Logger.debug("Network status: \(self.isConnected ? "connected" : "disconnected"), type: \(self.connectionType)")
        }

        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    deinit {
        stop()
    }
}
