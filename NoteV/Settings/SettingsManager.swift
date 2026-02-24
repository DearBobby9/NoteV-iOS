import Foundation
import Combine

// MARK: - SettingsManager

/// Singleton that persists LLM provider, model, and API keys in UserDefaults.
/// Falls back to NoteVConfig compile-time defaults when no value is stored.
final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    // MARK: - UserDefaults Keys

    private enum Key {
        static let llmProvider = "notev_llm_provider"
        static let llmModel = "notev_llm_model"
        static let llmEndpointURL = "notev_llm_endpoint_url"
        static let openAIAPIKey = "notev_openai_api_key"
        static let anthropicAPIKey = "notev_anthropic_api_key"
        static let geminiAPIKey = "notev_gemini_api_key"
        static let customAPIKey = "notev_custom_api_key"
    }

    // MARK: - Default Models per Provider

    static let defaultModels: [NoteVConfig.LLMProvider: String] = [
        .gemini: "gemini-2.5-flash",
        .openai: "gpt-4o",
        .anthropic: "claude-sonnet-4-20250514",
        .custom: "",
    ]

    // MARK: - Stored Properties

    private let defaults = UserDefaults.standard

    var llmProvider: NoteVConfig.LLMProvider {
        get {
            guard let raw = defaults.string(forKey: Key.llmProvider),
                  let provider = NoteVConfig.LLMProvider(rawValue: raw) else {
                return NoteVConfig.NoteGeneration.llmProvider
            }
            return provider
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: Key.llmProvider)
        }
    }

    var llmModel: String {
        get {
            defaults.string(forKey: Key.llmModel) ?? NoteVConfig.NoteGeneration.llmModel
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.llmModel)
        }
    }

    var llmEndpointURL: String {
        get {
            defaults.string(forKey: Key.llmEndpointURL) ?? ""
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Key.llmEndpointURL)
        }
    }

    var openAIAPIKey: String {
        get { defaults.string(forKey: Key.openAIAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.openAIAPIKey) }
    }

    var anthropicAPIKey: String {
        get { defaults.string(forKey: Key.anthropicAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.anthropicAPIKey) }
    }

    var geminiAPIKey: String {
        get { defaults.string(forKey: Key.geminiAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.geminiAPIKey) }
    }

    var customAPIKey: String {
        get { defaults.string(forKey: Key.customAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.customAPIKey) }
    }

    // MARK: - Computed

    /// Returns the API key for the currently selected provider.
    var activeAPIKey: String {
        switch llmProvider {
        case .openai: return openAIAPIKey
        case .anthropic: return anthropicAPIKey
        case .gemini: return geminiAPIKey
        case .custom: return customAPIKey
        }
    }

    /// True when there is a non-empty API key for the current provider
    /// (and a valid endpoint URL for .custom).
    var isConfigured: Bool {
        let keyOK = !activeAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        if llmProvider == .custom {
            let endpointOK = !llmEndpointURL.trimmingCharacters(in: .whitespaces).isEmpty
            return keyOK && endpointOK
        }
        return keyOK
    }

    // MARK: - Reset

    func resetAll() {
        objectWillChange.send()
        defaults.removeObject(forKey: Key.llmProvider)
        defaults.removeObject(forKey: Key.llmModel)
        defaults.removeObject(forKey: Key.llmEndpointURL)
        defaults.removeObject(forKey: Key.openAIAPIKey)
        defaults.removeObject(forKey: Key.anthropicAPIKey)
        defaults.removeObject(forKey: Key.geminiAPIKey)
        defaults.removeObject(forKey: Key.customAPIKey)
        NSLog("[SettingsManager] All settings reset to defaults")
    }

    // MARK: - Init

    private init() {
        NSLog("[SettingsManager] Loaded — provider: \(llmProvider.rawValue), model: \(llmModel), configured: \(isConfigured)")
    }
}
