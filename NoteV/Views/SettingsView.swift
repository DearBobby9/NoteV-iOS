import SwiftUI

// MARK: - SettingsView

/// In-app settings for LLM provider, model, and API keys.
/// Persists to UserDefaults via SettingsManager.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    // Local state for editing (committed on Save — nothing writes to UserDefaults until Save)
    @State private var selectedProvider: NoteVConfig.LLMProvider = .gemini
    @State private var model: String = ""
    @State private var apiKeys: [NoteVConfig.LLMProvider: String] = [:]
    @State private var endpointURL: String = ""
    @State private var showResetAlert = false

    /// Binding into the local apiKeys dict for the currently selected provider.
    private var apiKey: Binding<String> {
        Binding(
            get: { apiKeys[selectedProvider] ?? "" },
            set: { apiKeys[selectedProvider] = $0 }
        )
    }

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Provider & Model
                Section(header: Text("LLM Provider")) {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Gemini").tag(NoteVConfig.LLMProvider.gemini)
                        Text("OpenAI").tag(NoteVConfig.LLMProvider.openai)
                        Text("Anthropic").tag(NoteVConfig.LLMProvider.anthropic)
                        Text("Custom").tag(NoteVConfig.LLMProvider.custom)
                    }
                    .onChange(of: selectedProvider) { newProvider in
                        onProviderChanged(to: newProvider)
                    }

                    TextField("Model", text: $model)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                // MARK: - API Key
                Section(header: Text(apiKeyLabel), footer: Text("Your key is stored locally on this device.")) {
                    SecureField("API Key", text: apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                // MARK: - Custom Endpoint
                if selectedProvider == .custom {
                    Section(header: Text("Endpoint URL"), footer: Text("Full URL including path, e.g. https://my-proxy.com/v1/chat/completions")) {
                        TextField("https://...", text: $endpointURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                }

                // MARK: - Reset
                Section {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                    }
                    .alert("Reset Settings?", isPresented: $showResetAlert) {
                        Button("Cancel", role: .cancel) {}
                        Button("Reset", role: .destructive) {
                            resetToDefaults()
                        }
                    } message: {
                        Text("This will clear all saved API keys and revert to default provider settings.")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadCurrentValues() }
        }
    }

    // MARK: - Helpers

    private var apiKeyLabel: String {
        switch selectedProvider {
        case .gemini: return "Gemini API Key"
        case .openai: return "OpenAI API Key"
        case .anthropic: return "Anthropic API Key"
        case .custom: return "API Key"
        }
    }

    private func loadCurrentValues() {
        selectedProvider = settings.llmProvider
        model = settings.llmModel
        endpointURL = settings.llmEndpointURL

        // Load all 4 keys into local state — nothing writes back until Save
        apiKeys = [
            .openai: settings.openAIAPIKey,
            .anthropic: settings.anthropicAPIKey,
            .gemini: settings.geminiAPIKey,
            .custom: settings.customAPIKey,
        ]
    }

    private func onProviderChanged(to newProvider: NoteVConfig.LLMProvider) {
        // Auto-fill default model if current model is empty or was the previous provider's default
        let previousDefault = SettingsManager.defaultModels[selectedProvider] ?? ""
        let newDefault = SettingsManager.defaultModels[newProvider] ?? ""
        if model.isEmpty || model == previousDefault {
            model = newDefault
        }
        // Key switching is handled automatically by the apiKey Binding
    }

    private func save() {
        settings.llmProvider = selectedProvider
        settings.llmModel = model.trimmingCharacters(in: .whitespaces)
        settings.llmEndpointURL = endpointURL.trimmingCharacters(in: .whitespaces)

        // Write all keys from local state to UserDefaults
        settings.openAIAPIKey = (apiKeys[.openai] ?? "").trimmingCharacters(in: .whitespaces)
        settings.anthropicAPIKey = (apiKeys[.anthropic] ?? "").trimmingCharacters(in: .whitespaces)
        settings.geminiAPIKey = (apiKeys[.gemini] ?? "").trimmingCharacters(in: .whitespaces)
        settings.customAPIKey = (apiKeys[.custom] ?? "").trimmingCharacters(in: .whitespaces)

        NSLog("[SettingsView] Saved — provider: \(selectedProvider.rawValue), model: \(settings.llmModel), configured: \(settings.isConfigured)")
        dismiss()
    }

    private func resetToDefaults() {
        settings.resetAll()
        loadCurrentValues()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
