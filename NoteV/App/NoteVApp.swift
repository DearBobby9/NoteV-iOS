import SwiftUI
import MWDATCore

// MARK: - NoteVApp

@main
struct NoteVApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Configure Meta DAT SDK (VisionClaw pattern)
        do {
            try Wearables.configure()
            NSLog("[NoteVApp] Meta DAT SDK configured")
        } catch {
            NSLog("[NoteVApp] DAT SDK configure failed: \(error.localizedDescription)")
        }

        // Validate API keys
        APIKeys.validateAll()

        NSLog("[NoteVApp] App initialized")
    }

    var body: some Scene {
        WindowGroup {
            StartSessionView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}
