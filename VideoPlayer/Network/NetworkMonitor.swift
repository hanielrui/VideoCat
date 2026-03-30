import Foundation
import Network

// MARK: - 网络状态监控
class NetworkMonitor {

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

            self.onStatusChange?(self.isConnected)
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
