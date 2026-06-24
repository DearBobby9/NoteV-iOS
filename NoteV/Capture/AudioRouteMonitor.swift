import AVFoundation
import Foundation

// MARK: - AudioRouteMonitor

/// Observes AVAudioSession route changes during glasses sessions.
final class AudioRouteMonitor {

    private var observer: NSObjectProtocol?

    var onGlassesMicLost: (() -> Void)?

    func startMonitoringGlassesHFP() {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard !GlassesHFPRoute.isActive() else { return }
            NSLog("[AudioRouteMonitor] Glasses HFP route lost")
            self?.onGlassesMicLost?()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit {
        stop()
    }
}
