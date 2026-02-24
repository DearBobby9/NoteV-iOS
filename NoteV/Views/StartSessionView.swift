import SwiftUI

// MARK: - StartSessionView

/// Home screen: NoteV branding, glasses connection status, "Start Class" button, recent sessions.
/// TODO: Phase 2 — Wire up CaptureManager, session history, navigation
struct StartSessionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                NoteVConfig.Design.background
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    // Logo
                    VStack(spacing: 8) {
                        Image(systemName: "eye.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(NoteVConfig.Design.accent)

                        Text("NoteV")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(NoteVConfig.Design.textPrimary)

                        Text("Every AI note-taker can hear. Ours can see.")
                            .font(.subheadline)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }

                    // Connection Status
                    HStack(spacing: 12) {
                        Circle()
                            .fill(appState.isGlassesAvailable ? Color.green : NoteVConfig.Design.textSecondary)
                            .frame(width: 10, height: 10)

                        Text(appState.isGlassesAvailable ? "Glasses Connected" : "Using iPhone Camera")
                            .font(.callout)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(NoteVConfig.Design.surface)
                    .cornerRadius(NoteVConfig.Design.cornerRadius)

                    Spacer()

                    // Start Button
                    Button(action: {
                        NSLog("[StartSessionView] Start Class tapped")
                        // TODO: Phase 2 — Navigate to LiveSessionView + start recording
                    }) {
                        Text("Start Class")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(NoteVConfig.Design.accent)
                            .cornerRadius(NoteVConfig.Design.cornerRadius)
                    }
                    .padding(.horizontal, NoteVConfig.Design.padding)

                    // Recent Sessions
                    if !appState.pastSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Sessions")
                                .font(.headline)
                                .foregroundColor(NoteVConfig.Design.textPrimary)

                            // TODO: Phase 2 — SessionListView navigation
                            Text("No sessions yet")
                                .font(.subheadline)
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                        }
                        .padding(.horizontal, NoteVConfig.Design.padding)
                    }

                    Spacer()
                        .frame(height: 40)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Preview

#Preview {
    StartSessionView()
        .environmentObject(AppState())
}
