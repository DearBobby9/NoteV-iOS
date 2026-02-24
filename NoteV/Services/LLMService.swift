import Foundation

// MARK: - LLMService

/// Sends multimodal prompts to OpenAI GPT-4o or Anthropic Claude for note generation.
/// Uses native URLSession (no third-party HTTP client).
/// TODO: Phase 3 — Full API implementation with multimodal support
final class LLMService {

    // MARK: - Properties

    private let session = URLSession(configuration: .default)

    // MARK: - Init

    init() {
        NSLog("[LLMService] Initialized — provider: \(NoteVConfig.NoteGeneration.llmProvider.rawValue), model: \(NoteVConfig.NoteGeneration.llmModel)")
    }

    // MARK: - API Call

    /// Send a prompt with optional images to the configured LLM.
    func sendPrompt(
        systemPrompt: String,
        userPrompt: String,
        images: [Data] = []
    ) async throws -> String {
        NSLog("[LLMService] sendPrompt() called — provider: \(NoteVConfig.NoteGeneration.llmProvider.rawValue), images: \(images.count)")

        switch NoteVConfig.NoteGeneration.llmProvider {
        case .openai:
            return try await callOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
        case .anthropic:
            return try await callAnthropic(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
        }
    }

    // MARK: - OpenAI

    private func callOpenAI(systemPrompt: String, userPrompt: String, images: [Data]) async throws -> String {
        NSLog("[LLMService] callOpenAI() stub")
        // TODO: Phase 3
        // 1. Build request body with messages array
        // 2. Include base64-encoded images in content array
        // 3. POST to https://api.openai.com/v1/chat/completions
        // 4. Parse response and return content string
        return "OpenAI response stub — not yet implemented"
    }

    // MARK: - Anthropic

    private func callAnthropic(systemPrompt: String, userPrompt: String, images: [Data]) async throws -> String {
        NSLog("[LLMService] callAnthropic() stub")
        // TODO: Phase 3
        // 1. Build request body with system + messages
        // 2. Include base64-encoded images in content blocks
        // 3. POST to https://api.anthropic.com/v1/messages
        // 4. Parse response and return content string
        return "Anthropic response stub — not yet implemented"
    }
}
