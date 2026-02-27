import SwiftUI
import AVFoundation
import Speech

// MARK: - StartSessionView

/// Home screen: NoteV branding, glasses connection status, "Start Class" button, recent sessions.
struct StartSessionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sessionRecorder: SessionRecorder
    @StateObject private var captureManager = CaptureManager()
    @State private var showSettings = false
    @State private var selectedSource: CaptureSource = .phone

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

                // Glasses Connection Status
                GlassesConnectionCard(captureManager: captureManager)

                // Capture Source Picker (visible when glasses connected)
                if !captureManager.connectedDevices.isEmpty {
                    CaptureSourcePicker(selectedSource: $selectedSource)
                }

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
                        HStack(spacing: 8) {
                            Image(systemName: selectedSource == .glasses ? "eyeglasses" : "iphone")
                            Text("Start Class")
                        }
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
        .onChange(of: captureManager.connectedDevices) { oldDevices, newDevices in
            // Auto-select glasses when they first connect
            if oldDevices.isEmpty && !newDevices.isEmpty {
                selectedSource = .glasses
                NSLog("[StartSessionView] Glasses connected — auto-selected glasses source")
            }
            // Force phone when glasses disconnect and user had glasses selected
            else if !oldDevices.isEmpty && newDevices.isEmpty && selectedSource == .glasses {
                selectedSource = .phone
                NSLog("[StartSessionView] Glasses disconnected — falling back to phone source")
            }
        }
        .alert("Glasses Error", isPresented: Binding(
            get: { captureManager.glassesError != nil },
            set: { if !$0 { captureManager.dismissGlassesError() } }
        )) {
            Button("OK") { captureManager.dismissGlassesError() }
        } message: {
            Text(captureManager.glassesError ?? "")
        }
    }

    // MARK: - Actions

    private func startSession() {
        guard appState.sessionStatus != .starting && appState.sessionStatus != .recording else { return }
        let source = selectedSource
        NSLog("[StartSessionView] Start Class tapped — source: \(source.rawValue)")
        appState.reset()
        appState.sessionStatus = .starting

        Task {
            // Check permissions before starting recording
            let permissionsGranted = await checkPermissions()
            guard permissionsGranted else { return }

            // Re-validate glasses connectivity after async permission checks
            let finalSource: CaptureSource
            if source == .glasses && captureManager.connectedDevices.isEmpty {
                NSLog("[StartSessionView] Glasses disconnected during permission check — falling back to phone")
                finalSource = .phone
                selectedSource = .phone
            } else {
                finalSource = source
            }

            do {
                try await sessionRecorder.startRecording(preferredSource: finalSource)
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

// MARK: - GlassesConnectionCard

/// Interactive glasses connection status card with connect/disconnect actions.
private struct GlassesConnectionCard: View {
    @ObservedObject var captureManager: CaptureManager

    var body: some View {
        VStack(spacing: 10) {
            // Status row
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.callout)
                        .foregroundColor(NoteVConfig.Design.textPrimary)

                    if let name = captureManager.firstDeviceName {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                }

                Spacer()

                // Action button
                if captureManager.isRegistering {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                        .scaleEffect(0.8)
                } else if captureManager.isGlassesRegistered {
                    Button("Disconnect") {
                        captureManager.disconnectGlasses()
                    }
                    .font(.caption)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                } else {
                    Button("Connect Glasses") {
                        captureManager.connectGlasses()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(NoteVConfig.Design.accent)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(NoteVConfig.Design.surface)
        .cornerRadius(NoteVConfig.Design.cornerRadius)
        .padding(.horizontal, NoteVConfig.Design.padding)
    }

    private var statusColor: Color {
        if !captureManager.connectedDevices.isEmpty {
            return .green
        } else if captureManager.isRegistering {
            return .yellow
        } else {
            return NoteVConfig.Design.textSecondary
        }
    }

    private var statusText: String {
        if !captureManager.connectedDevices.isEmpty {
            return "Glasses Connected"
        } else if captureManager.isRegistering {
            return "Connecting..."
        } else if captureManager.isGlassesRegistered {
            return "Registered — Waiting for Glasses"
        } else {
            return "Using iPhone Camera"
        }
    }
}

// MARK: - CaptureSourcePicker

/// Two-option picker for selecting glasses or phone camera.
private struct CaptureSourcePicker: View {
    @Binding var selectedSource: CaptureSource

    var body: some View {
        HStack(spacing: 0) {
            sourceOption(
                source: .glasses,
                icon: "eyeglasses",
                label: "Glasses"
            )
            sourceOption(
                source: .phone,
                icon: "iphone",
                label: "iPhone"
            )
        }
        .background(NoteVConfig.Design.surface)
        .cornerRadius(NoteVConfig.Design.cornerRadius)
        .padding(.horizontal, NoteVConfig.Design.padding)
    }

    private func sourceOption(source: CaptureSource, icon: String, label: String) -> some View {
        let isSelected = selectedSource == source
        return Button {
            selectedSource = source
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.callout)
                Text(label)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .black : NoteVConfig.Design.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? NoteVConfig.Design.accent : Color.clear)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
        }
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
