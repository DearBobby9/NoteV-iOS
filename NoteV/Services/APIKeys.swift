import Foundation

// MARK: - APIKeys

/// Placeholder API keys. Replace with real keys before running.
/// In production, use Keychain or environment variables.
enum APIKeys {

    // MARK: - Deepgram (Streaming STT)

    static let deepgramAPIKey = "YOUR_DEEPGRAM_API_KEY"

    static var isDeepgramConfigured: Bool {
        deepgramAPIKey != "YOUR_DEEPGRAM_API_KEY" && !deepgramAPIKey.isEmpty
    }

    // MARK: - OpenAI (GPT-4o)

    static let openAIAPIKey = "YOUR_OPENAI_API_KEY"

    static var isOpenAIConfigured: Bool {
        openAIAPIKey != "YOUR_OPENAI_API_KEY" && !openAIAPIKey.isEmpty
    }

    // MARK: - Anthropic (Claude)

    static let anthropicAPIKey = "YOUR_ANTHROPIC_API_KEY"

    static var isAnthropicConfigured: Bool {
        anthropicAPIKey != "YOUR_ANTHROPIC_API_KEY" && !anthropicAPIKey.isEmpty
    }

    // MARK: - Google Gemini

    static let geminiAPIKey = "YOUR_GEMINI_API_KEY"

    static var isGeminiConfigured: Bool {
        geminiAPIKey != "YOUR_GEMINI_API_KEY" && !geminiAPIKey.isEmpty
    }

    // MARK: - Meta (DAT SDK)
    // MetaAppID=0 is Developer Mode (no ClientToken needed).
    // Replace with real Application ID from wearables.developer.meta.com for production.

    static let metaAppID = "0"

    static var isMetaConfigured: Bool {
        !metaAppID.isEmpty
    }

    // MARK: - Validation

    static func validateAll() {
        if !isDeepgramConfigured {
            NSLog("[APIKeys] WARNING: Deepgram API key not configured")
        }
        if !isOpenAIConfigured {
            NSLog("[APIKeys] WARNING: OpenAI API key not configured")
        }
        if !isAnthropicConfigured {
            NSLog("[APIKeys] WARNING: Anthropic API key not configured")
        }
        if !isGeminiConfigured {
            NSLog("[APIKeys] WARNING: Gemini API key not configured")
        }
        if !isMetaConfigured {
            NSLog("[APIKeys] WARNING: Meta App ID not configured")
        }
    }
}
