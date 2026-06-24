import AVFoundation
import Foundation

// MARK: - GlassesHFPRoute

/// Helpers for routing glasses microphone audio over Bluetooth HFP per Meta DAT docs.
/// https://wearables.developer.meta.com/docs/develop/dat/microphones-and-speakers/
enum GlassesHFPRoute {

    /// Whether the active input route includes Bluetooth HFP (glasses mic).
    static func isActive(on session: AVAudioSession = .sharedInstance()) -> Bool {
        session.currentRoute.inputs.contains { $0.portType == .bluetoothHFP }
    }

    /// Prefer the HFP input when glasses expose it as an available port.
    static func configurePreferredInput(on session: AVAudioSession = .sharedInstance()) throws {
        guard let hfpInput = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) else {
            return
        }
        try session.setPreferredInput(hfpInput)
        NSLog("[GlassesHFPRoute] Preferred input set to HFP: \(hfpInput.portName)")
    }

    /// Meta recommends ~2s for the HFP route to settle after starting AVAudioEngine.
    static func waitForActive(timeoutSeconds: TimeInterval = 2.5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if isActive() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isActive()
    }

    static var missingRouteError: NSError {
        NSError(
            domain: "GlassesCaptureProvider",
            code: -11,
            userInfo: [NSLocalizedDescriptionKey:
                "Glasses microphone not connected. Wear your glasses, confirm they appear in Meta AI, then try again. Audio must route through Bluetooth headset (HFP), not the iPhone mic."]
        )
    }
}
