import Foundation
import Network

@MainActor
@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kuro.networkmonitor")

    var isConnected: Bool = true
    var connectionType: ConnectionType = .unknown
    var reconnectionGeneration: Int = 0

    enum ConnectionType: Sendable {
        case wifi, cellular, wired, unknown
    }

    init() {
        startMonitoring()
    }

    /// A monitor frozen at `isConnected`: it never starts the path monitor, so nothing changes the state
    /// behind the caller's back (KuroTests, renders).
    init(fixedConnected isConnected: Bool) {
        self.isConnected = isConnected
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            let type = Self.detectConnectionType(path)
            Task { @MainActor [weak self] in
                self?.isConnected = connected
                self?.connectionType = type
                if connected { self?.reconnectionGeneration += 1 }
            }
        }
        monitor.start(queue: queue)
    }

    nonisolated private static func detectConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .unknown
    }

    deinit {
        monitor.cancel()
    }
}
