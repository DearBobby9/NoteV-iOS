import Foundation
import Network

// MARK: - NetworkConditions

enum NetworkConditions {

    /// True when the active network path is cellular. Deepgram live WebSocket is unreliable on LTE.
    static var isOnCellular: Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            result = path.status == .satisfied && path.usesInterfaceType(.cellular)
            semaphore.signal()
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        _ = semaphore.wait(timeout: .now() + 1)
        monitor.cancel()
        return result
    }
}
