import Foundation

// MARK: - UnifiedChatService

/// Single chat service for all AI interactions.
/// Replaces ChatService + CourseSetupChatService.
/// Supports: Q&A, course setup, settings config, reminders — all via natural language.
/// Actions are routed through <action> XML tags in LLM responses.
@MainActor
final class UnifiedChatService: ObservableObject {

    // MARK: - Published State

    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false

    // MARK: - Dependencies

    private(set) var conversationId: UUID
    private let chatStore = ChatStore.shared
    private let llmService = LLMService()
    private let courseStore = CourseStore()
    private let settings = SettingsManager.shared
    private var sessionContext: SessionData?

    private let maxHistoryMessages = 10
    var activeSendTask: Task<Void, Never>?

    // MARK: - Init

    init(conversationId: UUID, sessionContext: SessionData? = nil) {
        self.conversationId = conversationId
        self.sessionContext = sessionContext
        loadHistory()
        NSLog("[UnifiedChatService] Init — conversation: \(conversationId.uuidString.prefix(8)), session: \(sessionContext != nil), messages: \(messages.count)")
    }

    // MARK: - Switch Conversation

    func switchConversation(to newId: UUID) {
        activeSendTask?.cancel()
        activeSendTask = nil
        conversationId = newId
        messages = chatStore.loadConversation(id: newId)
        isLoading = false
        NSLog("[UnifiedChatService] Switched to conversation: \(newId.uuidString.prefix(8)), messages: \(messages.count)")
    }

    // MARK: - Load History

    func loadHistory() {
        messages = chatStore.loadConversation(id: conversationId)
    }

    // MARK: - Send Message

    func sendMessage(_ text: String, images: [Data] = []) async {
        // Capture conversation ID to detect if user switches mid-request
        let activeConversationId = self.conversationId

        // Save attached images and collect filenames
        var imageFilenames: [String]? = nil
        if !images.isEmpty {
            var filenames: [String] = []
            for (i, imageData) in images.enumerated() {
                let filename = "img_\(UUID().uuidString.prefix(8))_\(i).jpg"
                chatStore.saveImage(imageData, conversationId: activeConversationId, filename: filename)
                filenames.append(filename)
            }
            imageFilenames = filenames
        }

        let userMessage = ChatMessage(
            role: .user,
            content: text,
            imageAttachments: imageFilenames
        )
        messages.append(userMessage)
        saveConversation()
        isLoading = true

        // Add streaming placeholder
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)

        do {
            let systemPrompt = buildSystemPrompt()
            let conversationPrompt = buildConversationPrompt(latestMessage: text)

            let response = try await llmService.sendPrompt(
                systemPrompt: systemPrompt,
                userPrompt: conversationPrompt,
                images: images
            )

            // If conversation switched during LLM call, discard the response
            guard self.conversationId == activeConversationId else {
                NSLog("[UnifiedChatService] Conversation switched during LLM call — discarding response")
                return
            }

            // Parse action from response
            let (cleanedContent, actionPayload) = parseActionFromResponse(response)

            // Update placeholder
            if let index = messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                messages[index].content = cleanedContent
                messages[index].isStreaming = false
                messages[index].actionPayload = actionPayload
            }

            NSLog("[UnifiedChatService] Response — \(cleanedContent.count) chars, action: \(actionPayload?.type.rawValue ?? "none")")
        } catch {
            // If conversation switched, don't update the wrong conversation
            guard self.conversationId == activeConversationId else { return }

            NSLog("[UnifiedChatService] Error: \(error.localizedDescription)")
            if let index = messages.lastIndex(where: { $0.id == assistantMessage.id }) {
                messages[index].content = "Sorry, I couldn't process that. \(error.localizedDescription)"
                messages[index].isStreaming = false
            }
        }

        // Only update if still on the same conversation
        guard self.conversationId == activeConversationId else { return }
        isLoading = false
        saveConversation()
    }

    // MARK: - Action Handling

    /// Execute a confirmed action from an action card.
    func confirmAction(messageId: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let payload = messages[index].actionPayload,
              payload.status == .pending else { return }

        messages[index].actionPayload?.status = .confirmed

        do {
            let confirmMsg: String
            switch payload.type {
            case .addCourses:
                confirmMsg = try executeAddCourses(payload.data)
            case .setSetting:
                try executeSetSetting(payload.data)
                confirmMsg = "Setting updated!"
            case .createReminder:
                try await executeCreateReminder(payload.data)
                confirmMsg = "Reminder created!"
            }
            messages.append(ChatMessage(role: .assistant, content: confirmMsg))
            NSLog("[UnifiedChatService] Action confirmed: \(payload.type.rawValue)")
        } catch {
            messages[index].actionPayload?.status = .pending
            messages.append(ChatMessage(role: .assistant, content: "Failed: \(error.localizedDescription)"))
            NSLog("[UnifiedChatService] Action failed: \(error.localizedDescription)")
        }

        saveConversation()
    }

    /// Cancel a pending action.
    func cancelAction(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].actionPayload?.status == .pending else { return }

        messages[index].actionPayload?.status = .cancelled
        messages.append(ChatMessage(role: .assistant, content: "No problem, cancelled."))
        saveConversation()
    }

    // MARK: - Action Executors

    @discardableResult
    private func executeAddCourses(_ jsonData: String) throws -> String {
        guard let data = jsonData.data(using: .utf8),
              let coursesArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ActionError.parseError("Invalid courses data")
        }

        let colors = ["#00E5FF", "#FF6B35", "#7C4DFF", "#00E676", "#FF4081", "#FFD740"]
        let existingCourses = courseStore.loadAll()
        var addedCount = 0
        var skippedNames: [String] = []

        for (index, courseJson) in coursesArray.enumerated() {
            guard let name = courseJson["name"] as? String else { continue }
            let professor = courseJson["professor"] as? String
            let location = courseJson["location"] as? String

            var entries: [CourseScheduleEntry] = []
            if let scheduleArray = courseJson["schedule"] as? [[String: Any]] {
                for slot in scheduleArray {
                    guard let dayStr = slot["day"] as? String,
                          let startStr = slot["start"] as? String,
                          let endStr = slot["end"] as? String else { continue }

                    let dayOfWeek = parseDayOfWeek(dayStr)
                    let (startH, startM) = parseTime(startStr)
                    let (endH, endM) = parseTime(endStr)

                    entries.append(CourseScheduleEntry(
                        dayOfWeek: dayOfWeek,
                        startHour: startH,
                        startMinute: startM,
                        endHour: endH,
                        endMinute: endM
                    ))
                }
            }

            // Skip duplicate: same name (case-insensitive) and same schedule
            let isDuplicate = existingCourses.contains { existing in
                existing.name.lowercased() == name.lowercased() &&
                existing.schedule.count == entries.count &&
                existing.schedule.allSatisfy { ex in
                    entries.contains { e in
                        e.dayOfWeek == ex.dayOfWeek &&
                        e.startHour == ex.startHour && e.startMinute == ex.startMinute &&
                        e.endHour == ex.endHour && e.endMinute == ex.endMinute
                    }
                }
            }

            if isDuplicate {
                skippedNames.append(name)
                NSLog("[UnifiedChatService] Skipped duplicate course: \(name)")
                continue
            }

            let color = colors[(existingCourses.count + addedCount) % colors.count]
            addedCount += 1
            courseStore.add(Course(
                name: name,
                professor: professor,
                location: location,
                schedule: entries,
                color: color
            ))
        }

        NSLog("[UnifiedChatService] Added \(addedCount) courses, skipped \(skippedNames.count) duplicates")

        if addedCount == 0 && !skippedNames.isEmpty {
            return "These courses already exist: \(skippedNames.joined(separator: ", ")). No changes made."
        } else if !skippedNames.isEmpty {
            return "Courses added! Skipped duplicates: \(skippedNames.joined(separator: ", ")). Tap the calendar icon to view your schedule."
        }
        return "Courses added! Tap the calendar icon on the home screen to view your schedule."
    }

    private func executeSetSetting(_ jsonData: String) throws {
        guard let data = jsonData.data(using: .utf8),
              let settingJson = try JSONSerialization.jsonObject(with: data) as? [String: String],
              let key = settingJson["key"],
              let value = settingJson["value"] else {
            throw ActionError.parseError("Invalid setting data")
        }

        switch key {
        case "llm_provider":
            if let provider = NoteVConfig.LLMProvider(rawValue: value) {
                settings.llmProvider = provider
                // Auto-set default model for the provider
                if let defaultModel = SettingsManager.defaultModels[provider] {
                    settings.llmModel = defaultModel
                }
            }
        case "llm_model":
            settings.llmModel = value
        case "openai_api_key":
            settings.openAIAPIKey = value
        case "anthropic_api_key":
            settings.anthropicAPIKey = value
        case "gemini_api_key":
            settings.geminiAPIKey = value
        case "custom_api_key":
            settings.customAPIKey = value
        case "llm_endpoint_url":
            settings.llmEndpointURL = value
        default:
            throw ActionError.unknownSetting(key)
        }

        NSLog("[UnifiedChatService] Setting updated: \(key)")
    }

    private func executeCreateReminder(_ jsonData: String) async throws {
        guard let data = jsonData.data(using: .utf8),
              let reminderJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = reminderJson["title"] as? String else {
            throw ActionError.parseError("Invalid reminder data")
        }

        let service = ReminderSyncService.shared
        let granted = try await service.requestAccess()
        guard granted else {
            throw ActionError.accessDenied("Reminders access denied")
        }

        // Create a minimal TodoItem for the sync service
        let dateQuote = reminderJson["due"] as? String
        let isCalendar = reminderJson["is_calendar_event"] as? Bool ?? false

        let todo = TodoItem(
            title: title,
            category: .other,
            priority: .medium,
            dateQuote: dateQuote,
            resolvedDueDate: dateQuote.flatMap { parseDateString($0) },
            isCalendarEvent: isCalendar,
            sourceTimestamp: 0,
            sourceQuote: "",
            confidence: 5
        )

        _ = try await service.exportToReminders([todo], sessionTitle: "Chat", sessionId: nil)
        NSLog("[UnifiedChatService] Reminder created: \(title)")
    }

    // MARK: - Response Parsing

    /// Extract <action>JSON</action> from LLM response and create ActionPayload.
    private func parseActionFromResponse(_ response: String) -> (String, ActionPayload?) {
        // Look for <action>...</action> pattern
        guard let actionStart = response.range(of: "<action>"),
              let actionEnd = response.range(of: "</action>") else {
            return (response, nil)
        }

        let jsonString = String(response[actionStart.upperBound..<actionEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove the <action> block from display text
        var cleanedResponse = response
        let fullRange = actionStart.lowerBound..<actionEnd.upperBound
        cleanedResponse.removeSubrange(fullRange)
        cleanedResponse = cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse JSON to determine action type
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = json["type"] as? String else {
            return (response, nil)
        }

        let actionType: ActionPayload.ActionType
        var actionData: String

        switch typeStr {
        case "add_courses":
            actionType = .addCourses
            // Store just the courses array as the action data
            if let courses = json["courses"] {
                let coursesData = try? JSONSerialization.data(withJSONObject: courses)
                actionData = coursesData.flatMap { String(data: $0, encoding: .utf8) } ?? jsonString
            } else {
                actionData = jsonString
            }
        case "set_setting":
            actionType = .setSetting
            // Store key+value as action data
            let settingObj: [String: String] = [
                "key": json["key"] as? String ?? "",
                "value": json["value"] as? String ?? ""
            ]
            let settingData = try? JSONSerialization.data(withJSONObject: settingObj)
            actionData = settingData.flatMap { String(data: $0, encoding: .utf8) } ?? jsonString
        case "create_reminder":
            actionType = .createReminder
            actionData = jsonString
        default:
            return (response, nil)
        }

        let payload = ActionPayload(type: actionType, data: actionData, status: .pending)
        return (cleanedResponse, payload)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        var prompt = """
        You are NoteV's AI assistant. You help students manage their classes, notes, and study schedule.
        Be concise, friendly, and helpful.

        ## Available Actions
        When the user wants you to perform an action, respond with a JSON action block
        wrapped in <action> tags, followed by a natural language confirmation message.

        ### add_courses
        <action>{"type":"add_courses","courses":[{"name":"CS229 Machine Learning","schedule":[{"day":"Mon","start":"10:00","end":"11:15"},{"day":"Wed","start":"10:00","end":"11:15"}],"color":"#00E5FF"}]}</action>
        I'll add CS229 (Mon/Wed 10:00-11:15). Confirm?

        ### set_setting
        <action>{"type":"set_setting","key":"llm_provider","value":"anthropic"}</action>
        I'll switch your AI provider to Anthropic Claude. Confirm?

        Valid setting keys: llm_provider (openai/anthropic/gemini/custom), llm_model, openai_api_key, anthropic_api_key, gemini_api_key, custom_api_key, llm_endpoint_url

        ### create_reminder
        <action>{"type":"create_reminder","title":"Submit homework","due":"2026-03-15","is_calendar_event":false}</action>
        I'll create a reminder for "Submit homework" due March 15. Confirm?

        ## Course Setup Guidelines
        When a user wants to set up courses, extract ALL courses from their input in ONE response.
        Only ask follow-up if required fields (name, days, times) are truly missing.
        NEVER ask for professor name or classroom location — only ask for course name and schedule.
        If user sends an image of their schedule, extract all visible courses.

        ## Behavior Rules
        - Be concise and friendly
        - Use <action> tags for actionable operations (never just text for actions)
        - For questions/conversation, respond normally (no action tags)
        - When user sends an image, analyze it for schedule/course/slide info
        - For API key configuration: accept the key and use set_setting action
        """

        // Inject current context
        prompt += "\n\n## Current Context\n"

        // Current courses
        let courses = courseStore.loadAll()
        if courses.isEmpty {
            prompt += "- No courses set up yet\n"
        } else {
            prompt += "- Courses: \(courses.map(\.name).joined(separator: ", "))\n"
        }

        // Settings summary
        prompt += "- AI Provider: \(settings.llmProvider.rawValue), Model: \(settings.llmModel)\n"
        prompt += "- API Key configured: \(settings.isConfigured ? "Yes" : "No")\n"

        // Session context (if viewing a recorded session)
        if let session = sessionContext {
            prompt += "\n## Session Context\n"
            prompt += "Title: \(session.metadata.title)\n"

            let transcript = session.polishedTranscript?.segments.map(\.text).joined(separator: " ")
                ?? session.fullTranscript
            if !transcript.isEmpty {
                prompt += "Transcript (summary): \(String(transcript.prefix(8000)))\n"
            }

            if let notes = session.notes {
                prompt += "Notes title: \(notes.title)\n"
                prompt += "Summary: \(notes.summary)\n"
                for section in notes.sections.sorted(by: { $0.order < $1.order }) {
                    prompt += "- \(section.title): \(String(section.content.prefix(500)))\n"
                }
            }

            if let slides = session.slideAnalysis?.uniqueSlides.filter({ $0.extractedText != nil }) {
                prompt += "Slides: \(slides.count) unique slides\n"
                for slide in slides.prefix(20) {
                    prompt += "  Slide \(slide.slideNumber): \(slide.extractedText ?? "")\n"
                }
            }

            if let todos = session.todos, !todos.isEmpty {
                prompt += "Action items: \(todos.map(\.title).joined(separator: "; "))\n"
            }
        }

        return prompt
    }

    private func buildConversationPrompt(latestMessage: String) -> String {
        let recentMessages = messages
            .filter { !$0.isStreaming } // exclude streaming placeholders
            .dropLast(1) // exclude latest user message (sent separately below)
            .suffix(maxHistoryMessages)
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")

        if recentMessages.isEmpty {
            return "User: \(latestMessage)"
        }

        return """
        Previous conversation:
        \(recentMessages)

        User: \(latestMessage)
        """
    }

    // MARK: - Persistence

    private func saveConversation() {
        chatStore.saveConversation(id: conversationId, messages: messages)
    }

    // MARK: - Helpers

    private func parseDayOfWeek(_ str: String) -> Int {
        switch str.lowercased().prefix(3) {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        case "sat": return 7
        default: return 2
        }
    }

    private func parseTime(_ str: String) -> (Int, Int) {
        let parts = str.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return (9, 0)
        }
        return (hour, minute)
    }

    private func parseDateString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }
}

// MARK: - ActionError

enum ActionError: LocalizedError {
    case parseError(String)
    case unknownSetting(String)
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return "Parse error: \(msg)"
        case .unknownSetting(let key): return "Unknown setting: \(key)"
        case .accessDenied(let msg): return msg
        }
    }
}
