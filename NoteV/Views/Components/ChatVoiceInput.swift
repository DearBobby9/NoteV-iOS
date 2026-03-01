import SwiftUI

// MARK: - ChatVoiceInput

/// Deepgram-powered voice input for chat.
/// Tap mic to start, tap again to stop. Auto-stops on 5s silence (UtteranceEnd).
/// No time limit — Deepgram handles unlimited speech.
struct ChatVoiceInput: View {
    var onTextRecognized: (String) -> Void
    var onInterimUpdate: ((String) -> Void)?

    @State private var isListening = false
    @State private var listenTask: Task<Void, Never>?
    @State private var interimListenTask: Task<Void, Never>?
    @State private var pulseAnimation = false
    @State private var voiceService = DeepgramVoiceService()
    @State private var hasDeliveredTranscript = false

    var body: some View {
        Button(action: toggleListening) {
            ZStack {
                // Pulse ring when recording
                if isListening {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )
                }

                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundColor(isListening ? .red : NoteVConfig.Design.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        (isListening ? Color.red : NoteVConfig.Design.accent).opacity(0.15)
                    )
                    .cornerRadius(22)
            }
        }
    }

    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        isListening = true
        pulseAnimation = true
        hasDeliveredTranscript = false

        // Create fresh service for each session (stream can only be consumed once)
        voiceService = DeepgramVoiceService()

        listenTask = Task {
            do {
                try await voiceService.startListening()

                // Listen for interim updates
                interimListenTask = Task {
                    for await text in voiceService.interimTextStream {
                        await MainActor.run {
                            onInterimUpdate?(text)
                        }
                    }
                }

                // Wait for auto-stop (UtteranceEnd) or manual stop
                while await voiceService.isListening {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll
                    if Task.isCancelled { break }
                }

                // Get final transcript (DeepgramVoiceService already stopped itself)
                let transcript = await voiceService.stopListening()
                await MainActor.run {
                    isListening = false
                    pulseAnimation = false
                    if !transcript.isEmpty && !hasDeliveredTranscript {
                        hasDeliveredTranscript = true
                        onTextRecognized(transcript)
                    }
                    onInterimUpdate?("")
                }
            } catch {
                NSLog("[ChatVoiceInput] Error: \(error.localizedDescription)")
                await MainActor.run {
                    isListening = false
                    pulseAnimation = false
                }
            }
        }
    }

    private func stopListening() {
        // Cancel the polling loop — let it handle transcript delivery
        listenTask?.cancel()
        interimListenTask?.cancel()
        interimListenTask = nil

        // Get transcript directly since we cancelled the polling loop
        Task {
            let transcript = await voiceService.stopListening()
            await MainActor.run {
                isListening = false
                pulseAnimation = false
                if !transcript.isEmpty && !hasDeliveredTranscript {
                    hasDeliveredTranscript = true
                    onTextRecognized(transcript)
                }
                onInterimUpdate?("")
                listenTask = nil
            }
        }
    }
}
