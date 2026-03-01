import Foundation

// MARK: - LLMError

enum LLMError: LocalizedError {
    case notConfigured(String)
    case apiError(String)
    case parseError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let msg): return "LLM not configured: \(msg)"
        case .apiError(let msg): return "API error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

// MARK: - LLMService

/// Sends multimodal prompts to OpenAI, Gemini, Anthropic, or any OpenAI-compatible endpoint.
/// Uses native URLSession (no third-party HTTP client).
final class LLMService {

    // MARK: - Default Endpoints

    private static let defaultEndpoints: [NoteVConfig.LLMProvider: String] = [
        .openai: "https://api.openai.com/v1/chat/completions",
        .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        .anthropic: "https://api.anthropic.com/v1/messages",
    ]

    // MARK: - Properties

    private let session: URLSession
    private let settings = SettingsManager.shared

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: config)
        NSLog("[LLMService] Initialized — provider: \(settings.llmProvider.rawValue), model: \(settings.llmModel), configured: \(settings.isConfigured)")
    }

    // MARK: - Resolve Helpers

    private func resolveEndpoint() throws -> URL {
        let provider = settings.llmProvider

        // Custom endpoint URL takes priority (required for .custom provider)
        let customURL = settings.llmEndpointURL
        if !customURL.isEmpty {
            guard let url = URL(string: customURL) else {
                throw LLMError.notConfigured("Invalid custom endpoint URL: \(customURL)")
            }
            return url
        }

        guard provider != .custom else {
            throw LLMError.notConfigured("Custom provider requires an endpoint URL — set it in Settings")
        }

        guard let urlString = Self.defaultEndpoints[provider],
              let url = URL(string: urlString) else {
            throw LLMError.notConfigured("No default endpoint for provider: \(provider.rawValue)")
        }
        return url
    }

    private func resolveAPIKey() throws -> String {
        let key = settings.activeAPIKey
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LLMError.notConfigured("API key not set for \(settings.llmProvider.rawValue) — open Settings to configure")
        }
        return key
    }

    // MARK: - API Call

    /// Send a prompt with optional images to the configured LLM.
    func sendPrompt(
        systemPrompt: String,
        userPrompt: String,
        images: [Data] = []
    ) async throws -> String {
        let provider = settings.llmProvider
        NSLog("[LLMService] sendPrompt() called — provider: \(provider.rawValue), model: \(settings.llmModel), images: \(images.count)")

        switch provider {
        case .openai, .gemini, .custom:
            let endpoint = try resolveEndpoint()
            let apiKey = try resolveAPIKey()
            return try await callOpenAICompatible(
                endpoint: endpoint,
                apiKey: apiKey,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            )
        case .anthropic:
            return try await callAnthropic(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
        }
    }

    // MARK: - OpenAI-Compatible (OpenAI, Gemini, Custom)

    private func callOpenAICompatible(
        endpoint: URL,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        images: [Data]
    ) async throws -> String {
        let model = settings.llmModel
        NSLog("[LLMService] callOpenAICompatible() — endpoint: \(endpoint.host ?? "?"), model: \(model), images: \(images.count)")

        // Build user content array (text + images)
        var userContent: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]

        for imageData in images {
            let base64 = imageData.base64EncodedString()
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)"
                ]
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": NoteVConfig.NoteGeneration.maxResponseTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        NSLog("[LLMService] Sending request — body size: \(request.httpBody?.count ?? 0) bytes")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Invalid response")
        }

        NSLog("[LLMService] Response — status: \(httpResponse.statusCode), size: \(data.count) bytes")

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            NSLog("[LLMService] API error: \(errorBody)")
            throw LLMError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        // Parse OpenAI-compatible response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError("Could not parse response from \(endpoint.host ?? "unknown")")
        }

        NSLog("[LLMService] Response parsed — \(content.count) chars")
        return content
    }

    // MARK: - Anthropic

    private func callAnthropic(systemPrompt: String, userPrompt: String, images: [Data]) async throws -> String {
        let apiKey = try resolveAPIKey()

        NSLog("[LLMService] callAnthropic() — images: \(images.count)")

        // Build user content blocks
        var contentBlocks: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]

        for imageData in images {
            let base64 = imageData.base64EncodedString()
            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ]
            ])
        }

        let body: [String: Any] = [
            "model": settings.llmModel,
            "max_tokens": NoteVConfig.NoteGeneration.maxResponseTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": contentBlocks]
            ]
        ]

        let endpoint = try resolveEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw LLMError.parseError("Could not parse Anthropic response")
        }

        NSLog("[LLMService] Anthropic response parsed — \(text.count) chars")
        return text
    }
}
