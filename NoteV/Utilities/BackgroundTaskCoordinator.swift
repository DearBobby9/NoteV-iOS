import UIKit

// MARK: - BackgroundTaskCoordinator

/// Extends execution time when the app moves to the background during long post-processing.
enum BackgroundTaskCoordinator {

    static func run<T>(
        named name: String,
        operation: @escaping () async -> T
    ) async -> T {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }

        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        return await operation()
    }
}
