import Foundation
import SwiftUI

// MARK: - CaptureManager

/// Manages capture provider selection and lifecycle.
/// Auto-selects glasses when connected, falls back to phone camera.
/// On Simulator (no camera/mic), starts with empty streams to avoid crashes.
@MainActor
final class CaptureManager: ObservableObject {

    // MARK: - Properties

    @Published private(set) var activeProvider: (any CaptureProvider)?
    @Published private(set) var activeSource: CaptureSource = .phone

    private let glassesProvider: GlassesCaptureProvider
    private let phoneProvider: PhoneCaptureProvider

    // MARK: - Init

    init() {
        self.glassesProvider = GlassesCaptureProvider()
        self.phoneProvider = PhoneCaptureProvider()
        NSLog("[CaptureManager] Initialized — default source: phone, phoneAvailable: \(phoneProvider.isAvailable)")
    }

    // MARK: - Provider Selection

    /// Select the best available capture provider.
    func selectProvider() -> any CaptureProvider {
        if glassesProvider.isAvailable {
            activeSource = .glasses
            activeProvider = glassesProvider
            NSLog("[CaptureManager] Selected glasses capture provider")
            return glassesProvider
        } else if phoneProvider.isAvailable {
            activeSource = .phone
            activeProvider = phoneProvider
            NSLog("[CaptureManager] Selected phone capture provider")
            return phoneProvider
        } else {
            // Simulator or no hardware — use phone provider anyway (it will produce empty streams)
            activeSource = .phone
            activeProvider = phoneProvider
            NSLog("[CaptureManager] WARNING: No capture hardware available (Simulator?) — using phone provider stub")
            return phoneProvider
        }
    }

    // MARK: - Lifecycle

    /// Start capture with the selected provider.
    func startCapture() async throws {
        let provider = selectProvider()
        do {
            try await provider.startCapture()
            NSLog("[CaptureManager] Capture started via \(activeSource.rawValue)")
        } catch {
            NSLog("[CaptureManager] WARNING: Capture start failed: \(error.localizedDescription) — continuing with empty streams")
            // Don't re-throw on Simulator so the app can still run the UI flow
            #if !targetEnvironment(simulator)
            throw error
            #endif
        }
    }

    /// Stop capture.
    func stopCapture() async {
        await activeProvider?.stopCapture()
        NSLog("[CaptureManager] Capture stopped")
    }
}
