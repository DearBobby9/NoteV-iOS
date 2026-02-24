import SwiftUI
import AVFoundation
import Speech

// MARK: - StartSessionView

/// Home screen: NoteV branding, glasses connection status, "Start Class" button, recent sessions.
struct StartSessionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sessionRecorder: SessionRecorder
    @State private var showSettings = false

    var body: some View {
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
                    startSession()
                }) {
                    if appState.sessionStatus == .starting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(NoteVConfig.Design.accent.opacity(0.7))
                            .cornerRadius(NoteVConfig.Design.cornerRadius)
                    } else {
                        Text("Start Class")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(NoteVConfig.Design.accent)
                            .cornerRadius(NoteVConfig.Design.cornerRadius)
                    }
                }
                .padding(.horizontal, NoteVConfig.Design.padding)
                .disabled(appState.sessionStatus == .starting || appState.sessionStatus == .recording)

                // Not-configured hint
                if !SettingsManager.shared.isConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("API key not configured — tap")
                        Image(systemName: "gearshape")
                        Text("to set up")
                    }
                    .font(.caption)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                }

                // Recent Sessions Button
                if !appState.pastSessions.isEmpty {
                    Button(action: {
                        appState.navigationPath.append(NavigationDestination.sessionList)
                    }) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("Past Sessions (\(appState.pastSessions.count))")
                        }
                        .font(.callout)
                        .foregroundColor(NoteVConfig.Design.accent)
                    }
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            loadPastSessions()
        }
    }

    // MARK: - Actions

    private func startSession() {
        guard appState.sessionStatus != .starting && appState.sessionStatus != .recording else { return }
        NSLog("[StartSessionView] Start Class tapped")
        appState.reset()
        appState.sessionStatus = .starting

        Task {
            // Check permissions before starting recording
            let permissionsGranted = await checkPermissions()
            guard permissionsGranted else { return }

            do {
                try await sessionRecorder.startRecording()
                appState.navigationPath.append(NavigationDestination.liveSession)
            } catch {
                NSLog("[StartSessionView] ERROR starting session: \(error.localizedDescription)")
                appState.sessionStatus = .error(error.localizedDescription)
            }
        }
    }

    private func checkPermissions() async -> Bool {
        // Camera
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        if !cameraGranted {
            NSLog("[StartSessionView] Camera permission denied")
            appState.sessionStatus = .error("Camera access is required to capture visual content. Please enable it in Settings > Privacy > Camera.")
            return false
        }

        // Microphone
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        if !micGranted {
            NSLog("[StartSessionView] Microphone permission denied")
            appState.sessionStatus = .error("Microphone access is required for lecture transcription. Please enable it in Settings > Privacy > Microphone.")
            return false
        }

        // Speech recognition
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        if speechStatus != .authorized {
            NSLog("[StartSessionView] Speech recognition permission denied: \(speechStatus.rawValue)")
            appState.sessionStatus = .error("Speech recognition is required for live transcription. Please enable it in Settings > Privacy > Speech Recognition.")
            return false
        }

        NSLog("[StartSessionView] All permissions granted")
        return true
    }

    private func loadPastSessions() {
        let store = SessionStore()
        appState.pastSessions = store.loadAllSessions()
        NSLog("[StartSessionView] Loaded \(appState.pastSessions.count) past sessions")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StartSessionView()
            .environmentObject(AppState())
            .environmentObject(SessionRecorder())
    }
}
