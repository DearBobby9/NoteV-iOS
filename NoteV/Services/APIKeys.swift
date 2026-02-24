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

    // MARK: - Meta (DAT SDK)

    static let metaAppID = "YOUR_META_APP_ID"
    static let metaClientToken = "YOUR_META_CLIENT_TOKEN"

    static var isMetaConfigured: Bool {
        metaAppID != "YOUR_META_APP_ID" && !metaAppID.isEmpty
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
        if !isMetaConfigured {
            NSLog("[APIKeys] WARNING: Meta App ID not configured")
        }
    }
}
