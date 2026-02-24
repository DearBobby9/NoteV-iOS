import Foundation
import SwiftUI

// MARK: - CaptureManager

/// Manages capture provider selection and lifecycle.
/// Auto-selects glasses when connected, falls back to phone camera.
/// TODO: Phase 1 — Full provider lifecycle management
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
        NSLog("[CaptureManager] Initialized — default source: phone")
    }

    // MARK: - Provider Selection

    /// Select the best available capture provider.
    func selectProvider() -> any CaptureProvider {
        if glassesProvider.isAvailable {
            activeSource = .glasses
            activeProvider = glassesProvider
            NSLog("[CaptureManager] Selected glasses capture provider")
            return glassesProvider
        } else {
            activeSource = .phone
            activeProvider = phoneProvider
            NSLog("[CaptureManager] Selected phone capture provider (fallback)")
            return phoneProvider
        }
    }

    // MARK: - Lifecycle

    /// Start capture with the selected provider.
    func startCapture() async throws {
        let provider = selectProvider()
        try await provider.startCapture()
        NSLog("[CaptureManager] Capture started via \(activeSource.rawValue)")
    }

    /// Stop capture.
    func stopCapture() async {
        await activeProvider?.stopCapture()
        NSLog("[CaptureManager] Capture stopped")
    }
}
