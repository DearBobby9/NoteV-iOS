import SwiftUI
import MWDATCore

// MARK: - NoteVApp

@main
struct NoteVApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var sessionRecorder = SessionRecorder()

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
            .preferredColorScheme(.dark)
            .task {
                sessionRecorder.setAppState(appState)
            }
            .onOpenURL { url in
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
                else { return }
                Task {
                    do {
                        _ = try await Wearables.shared.handleUrl(url)
                        NSLog("[NoteVApp] DAT callback handled: \(url)")
                    } catch {
                        NSLog("[NoteVApp] DAT callback error: \(error)")
                    }
                }
            }
        }
    }
}
