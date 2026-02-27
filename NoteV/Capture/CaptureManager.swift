import Foundation
import SwiftUI
import MWDATCore

// MARK: - CaptureManager

/// Manages capture provider selection, lifecycle, and glasses registration state.
/// Auto-selects glasses when connected, falls back to phone camera.
/// On Simulator (no camera/mic), starts with empty streams to avoid crashes.
@MainActor
final class CaptureManager: ObservableObject {

    // MARK: - Properties

    @Published private(set) var activeProvider: (any CaptureProvider)?
    @Published private(set) var activeSource: CaptureSource = .phone

    // Glasses registration state (for UI)
    @Published private(set) var registrationState: RegistrationState
    @Published private(set) var connectedDevices: [DeviceIdentifier] = []
    @Published var glassesError: String?

    private let glassesProvider: GlassesCaptureProvider
    private let phoneProvider: PhoneCaptureProvider
    private let wearables: WearablesInterface

    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?

    // MARK: - Computed

    var isGlassesRegistered: Bool {
        registrationState == .registered
    }

    var isRegistering: Bool {
        registrationState == .registering
    }

    var firstDeviceName: String? {
        guard let deviceId = connectedDevices.first,
              let device = wearables.deviceForIdentifier(deviceId) else { return nil }
        return device.nameOrId()
    }

    // MARK: - Init

    init(wearables: WearablesInterface = Wearables.shared) {
        self.wearables = wearables
        self.registrationState = wearables.registrationState
        self.glassesProvider = GlassesCaptureProvider(wearables: wearables)
        self.phoneProvider = PhoneCaptureProvider()

        NSLog("[CaptureManager] Initialized — registration: \(wearables.registrationState), phoneAvailable: \(phoneProvider.isAvailable)")

        // Monitor registration state
        registrationTask = Task { @MainActor [weak self, wearables] in
            for await state in wearables.registrationStateStream() {
                guard let self else { break }
                self.registrationState = state
                NSLog("[CaptureManager] Registration state: \(state)")
            }
        }

        // Monitor connected devices
        deviceStreamTask = Task { @MainActor [weak self, wearables] in
            for await devices in wearables.devicesStream() {
                guard let self else { break }
                self.connectedDevices = devices
                NSLog("[CaptureManager] Connected devices: \(devices.count)")
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
    }

    // MARK: - Glasses Connection

    func connectGlasses() {
        guard registrationState != .registering else { return }
        Task { @MainActor in
            do {
                try await wearables.startRegistration()
                NSLog("[CaptureManager] Registration started")
            } catch let error as RegistrationError {
                NSLog("[CaptureManager] Registration error (RegistrationError): \(error.description)")
                glassesError = error.description
            } catch {
                NSLog("[CaptureManager] Registration error: \(error)")
                glassesError = error.localizedDescription
            }
        }
    }

    func disconnectGlasses() {
        Task { @MainActor in
            do {
                try await wearables.startUnregistration()
                NSLog("[CaptureManager] Unregistration started")
            } catch let error as UnregistrationError {
                NSLog("[CaptureManager] Unregistration error: \(error.description)")
                glassesError = error.description
            } catch {
                NSLog("[CaptureManager] Unregistration error: \(error)")
                glassesError = error.localizedDescription
            }
        }
    }

    func dismissGlassesError() {
        glassesError = nil
    }

    // MARK: - Provider Selection

    /// Select capture provider based on user's explicit choice.
    /// When `preferredSource` is `.glasses`, uses glasses provider directly
    /// (bypasses async isAvailable check — the UI already confirmed glasses are connected).
    func selectProvider(preferredSource: CaptureSource = .phone) -> any CaptureProvider {
        if preferredSource == .glasses {
            activeSource = .glasses
            activeProvider = glassesProvider
            NSLog("[CaptureManager] Selected glasses capture provider (user choice)")
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

    /// Start capture with the user-selected provider.
    func startCapture(preferredSource: CaptureSource = .phone) async throws {
        let provider = selectProvider(preferredSource: preferredSource)
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
