import SwiftUI
import MWDATCore

// MARK: - NoteVApp

@main
struct NoteVApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var sessionRecorder = SessionRecorder()
    @StateObject private var captureManager = CaptureManager()

    init() {
        // Configure Meta DAT SDK (VisionClaw pattern)
        do {
            try Wearables.configure()
            NSLog("[NoteVApp] Meta DAT SDK configured")
        } catch {
            NSLog("[NoteVApp] DAT SDK configure failed: \(error.localizedDescription)")
        }

        NSLog("[NoteVApp] App initialized — LLM configured: \(SettingsManager.shared.isConfigured)")
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $appState.navigationPath) {
                StartSessionView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .liveSession:
                            LiveSessionView()
                        case .notesResult:
                            NotesResultView()
                        case .sessionResult:
                            SessionResultView()
                        case .pastSessionResult:
                            SessionResultView(isBrowsingPastSession: true)
                        case .sessionList:
                            SessionListView()
                        }
                    }
            }
            .environmentObject(appState)
            .environmentObject(sessionRecorder)
            .environmentObject(captureManager)
            .preferredColorScheme(.dark)
            .task {
                sessionRecorder.setAppState(appState)
                sessionRecorder.setCaptureManager(captureManager)
            }
            // Meta sample pattern: handle DAT callbacks at the root scene, not inside nested views.
            .onOpenURL { url in
                handleWearablesCallback(url)
            }
        }
    }

    /// Forward Meta AI deep links to the DAT SDK so registration can complete.
    private func handleWearablesCallback(_ url: URL) {
        NSLog("[NoteVApp] Received URL: \(url.absoluteString)")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let isDATCallback = components?.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
            || url.scheme?.lowercased() == "notev"

        guard isDATCallback else {
            NSLog("[NoteVApp] Ignoring non-DAT URL")
            return
        }

        Task { @MainActor in
            do {
                let handled = try await Wearables.shared.handleUrl(url)
                NSLog("[NoteVApp] DAT callback handled (handled=\(handled)): \(url)")
            } catch let error as RegistrationError {
                NSLog("[NoteVApp] DAT registration callback error: \(error.description)")
                captureManager.glassesError = error.description
            } catch {
                NSLog("[NoteVApp] DAT callback error: \(error.localizedDescription)")
                captureManager.glassesError = error.localizedDescription
            }
        }
    }
}
