import SwiftUI

// MARK: - NoteVConfig

/// Centralized configuration for all tunable parameters.
enum NoteVConfig {

    // MARK: - Frame Capture

    enum Frame {
        /// Seconds between periodic frame samples
        static let periodicSamplingInterval: TimeInterval = 5.0
        /// SSIM threshold below which a frame is considered "changed"
        static let changeDetectionThreshold: Double = 0.15
        /// Number of burst frames to capture on change detection
        static let burstFrameCount: Int = 3
        /// Maximum frames stored per session (battery budget)
        static let maxFramesPerSession: Int = 500
    }

    // MARK: - Audio / STT

    enum Audio {
        /// Which STT provider to use
        static let sttProvider: STTProvider = .deepgram
        /// Deepgram model identifier
        static let deepgramModel: String = "nova-2"
        /// Audio sample rate in Hz
        static let sampleRate: Int = 16_000
        /// Audio bit depth
        static let bitDepth: Int = 16
        /// Number of audio channels
        static let channels: Int = 1
    }

    enum STTProvider: String {
        case deepgram
        case appleSpeech
    }

    // MARK: - Bookmark

    enum Bookmark {
        /// Voice keyword that triggers a bookmark
        static let keyword: String = "mark"
        /// Minimum seconds between bookmark triggers
        static let cooldownSeconds: TimeInterval = 3.0
        /// Seconds of transcript context to capture around bookmark
        static let transcriptContextWindow: TimeInterval = 15.0
    }

    // MARK: - Note Generation

    enum NoteGeneration {
        /// Which LLM provider to use
        static let llmProvider: LLMProvider = .openai
        /// LLM model identifier
        static let llmModel: String = "gpt-4o"
        /// Maximum frames included in the LLM prompt
        static let maxFramesInPrompt: Int = 20
        /// Maximum tokens for LLM response
        static let maxResponseTokens: Int = 4096
    }

    enum LLMProvider: String {
        case openai
        case anthropic
    }

    // MARK: - Storage

    enum Storage {
        /// JPEG compression quality for stored frames (0.0–1.0)
        static let jpegCompressionQuality: CGFloat = 0.8
        /// Directory name for session data
        static let sessionsDirectory: String = "NoteVSessions"
    }

    // MARK: - Design System

    enum Design {
        static let background = Color(hex: 0x0D1117)
        static let surface = Color(hex: 0x161B22)
        static let accent = Color(hex: 0x00E5FF)
        static let textPrimary = Color.white
        static let textSecondary = Color(hex: 0x8B949E)
        static let bookmarkHighlight = Color(hex: 0xFF6B35)

        static let cornerRadius: CGFloat = 12
        static let padding: CGFloat = 16
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
