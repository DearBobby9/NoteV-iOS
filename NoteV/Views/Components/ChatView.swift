import SwiftUI
import PhotosUI

// MARK: - ChatView

/// Unified chat UI used from Home Screen and Session Result.
/// Supports: text input, Deepgram voice input, image attachment, action cards.
/// Home chats support New Chat + Chat History; session chats are single-conversation.
struct ChatView: View {
    let sessionContext: SessionData?

    @StateObject private var chatService: UnifiedChatService
    @State private var inputText = ""
    @State private var interimVoiceText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingImages: [Data] = []
    @State private var showHistory = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(conversationId: UUID, sessionContext: SessionData? = nil) {
        self.sessionContext = sessionContext
        self._chatService = StateObject(wrappedValue: UnifiedChatService(
            conversationId: conversationId,
            sessionContext: sessionContext
        ))
    }

    private var isHomeChat: Bool { sessionContext == nil }

    var body: some View {
        NavigationView {
            ZStack {
                NoteVConfig.Design.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    messagesView
                    if !interimVoiceText.isEmpty {
                        interimVoiceBar
                    }
                    inputBar
                }
            }
            .navigationTitle(isHomeChat ? "NoteV AI" : "Ask about this lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(NoteVConfig.Design.accent)
                }

                if isHomeChat {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button(action: { showHistory = true }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(NoteVConfig.Design.accent)
                        }

                        Button(action: startNewChat) {
                            Image(systemName: "plus.bubble")
                                .foregroundColor(NoteVConfig.Design.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                ChatHistoryView { selectedId in
                    chatService.switchConversation(to: selectedId)
                    clearInputState()
                }
            }
        }
    }

    // MARK: - Messages

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if chatService.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chatService.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, NoteVConfig.Design.padding)
                .padding(.vertical, 12)
            }
            .onChange(of: chatService.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = chatService.messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: isHomeChat ? "sparkles" : "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(NoteVConfig.Design.accent.opacity(0.6))

            if isHomeChat {
                Text("I'm your AI assistant")
                    .font(.headline)
                    .foregroundColor(NoteVConfig.Design.textPrimary)

                Text("I can help you set up courses, configure settings, create reminders, and answer questions.")
                    .font(.subheadline)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            } else {
                Text("Ask me anything about this lecture!")
                    .font(.headline)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
            }

            suggestedChips
        }
    }

    private var suggestedChips: some View {
        let chips: [(String, String)] = isHomeChat
            ? [
                ("Set up my courses", "book"),
                ("Configure API settings", "gearshape"),
                ("Create a reminder", "clock"),
                ("What can you do?", "questionmark.circle")
            ]
            : [
                ("Summarize key points", "doc.text"),
                ("What assignments were mentioned?", "checklist"),
                ("Explain the formula discussed", "function"),
                ("Remind me to review this", "clock")
            ]

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(chips, id: \.0) { text, icon in
                Button {
                    inputText = text
                    sendMessage()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.caption)
                        Text(text)
                            .font(.subheadline)
                    }
                    .foregroundColor(NoteVConfig.Design.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(NoteVConfig.Design.accent.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
    }

    // MARK: - Message Row

    private func messageRow(_ message: ChatMessage) -> some View {
        VStack(spacing: 8) {
            messageBubble(message)

            // Action card (if present)
            if let payload = message.actionPayload {
                actionCard(message: message, payload: payload)
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Image attachments
                if let attachments = message.imageAttachments, !attachments.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(attachments, id: \.self) { filename in
                            if let imageData = ChatStore.shared.loadImage(
                                conversationId: chatService.conversationId, filename: filename
                            ), let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }

                if message.isStreaming && message.content.isEmpty {
                    typingIndicator
                } else {
                    let textColor: Color = message.role == .user ? .black : NoteVConfig.Design.textPrimary
                    Group {
                        if message.isStreaming {
                            Text(message.content)
                                .foregroundColor(textColor)
                        } else {
                            Text(markdownAttributedString(message.content, foregroundColor: textColor))
                        }
                    }
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? NoteVConfig.Design.accent
                            : NoteVConfig.Design.surface
                    )
                    .cornerRadius(16)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.5))
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75,
                   alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer() }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(NoteVConfig.Design.textSecondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NoteVConfig.Design.surface)
        .cornerRadius(16)
    }

    // MARK: - Action Card

    private func actionCard(message: ChatMessage, payload: ActionPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: actionIcon(payload.type))
                    .foregroundColor(NoteVConfig.Design.accent)
                Text(actionTitle(payload.type))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(NoteVConfig.Design.textPrimary)
            }

            // Action data summary
            actionDataSummary(payload)

            // Buttons (only if pending)
            if payload.status == .pending {
                HStack(spacing: 12) {
                    Button {
                        Task { await chatService.confirmAction(messageId: message.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text("Confirm")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(NoteVConfig.Design.accent)
                        .cornerRadius(8)
                    }

                    Button {
                        chatService.cancelAction(messageId: message.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                            Text("Cancel")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(NoteVConfig.Design.surface)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(NoteVConfig.Design.textSecondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            } else {
                Text(payload.status == .confirmed ? "Confirmed" : "Cancelled")
                    .font(.caption)
                    .foregroundColor(payload.status == .confirmed ? .green : NoteVConfig.Design.textSecondary)
            }
        }
        .padding(14)
        .background(NoteVConfig.Design.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NoteVConfig.Design.accent.opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: UIScreen.main.bounds.width * 0.85, alignment: .leading)
    }

    private func actionIcon(_ type: ActionPayload.ActionType) -> String {
        switch type {
        case .addCourses: return "book"
        case .setSetting: return "gearshape"
        case .createReminder: return "clock"
        }
    }

    private func actionTitle(_ type: ActionPayload.ActionType) -> String {
        switch type {
        case .addCourses: return "Add Courses"
        case .setSetting: return "Update Setting"
        case .createReminder: return "Create Reminder"
        }
    }

    private func actionDataSummary(_ payload: ActionPayload) -> some View {
        Group {
            if let data = payload.data.data(using: .utf8) {
                switch payload.type {
                case .addCourses:
                    if let courses = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(courses.indices, id: \.self) { i in
                                let course = courses[i]
                                let name = course["name"] as? String ?? "Unknown"
                                let schedule = formatScheduleSummary(course["schedule"] as? [[String: Any]])
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("  \(name)")
                                        .font(.caption)
                                        .foregroundColor(NoteVConfig.Design.textSecondary)
                                    if !schedule.isEmpty {
                                        Text("    \(schedule)")
                                            .font(.caption2)
                                            .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.7))
                                    }
                                }
                            }
                        }
                    }
                case .setSetting:
                    if let setting = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                        let key = setting["key"] ?? ""
                        let value = setting["value"] ?? ""
                        let displayValue = key.contains("api_key") ? "\(value.prefix(8))..." : value
                        Text("\(key): \(displayValue)")
                            .font(.caption)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                case .createReminder:
                    if let reminder = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let title = reminder["title"] as? String ?? ""
                        let due = reminder["due"] as? String ?? "No date"
                        Text("\(title) — \(due)")
                            .font(.caption)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                }
            }
        }
    }

    private func formatScheduleSummary(_ schedule: [[String: Any]]?) -> String {
        guard let schedule, !schedule.isEmpty else { return "" }
        let days = schedule.compactMap { slot -> String? in
            guard let day = slot["day"] as? String else { return nil }
            return shortDayLabel(day)
        }
        let uniqueDays = NSOrderedSet(array: days).array as? [String] ?? days
        let time = schedule.first.flatMap { slot -> String? in
            guard let start = slot["start"] as? String else { return nil }
            let end = slot["end"] as? String
            let startFormatted = formatTimeString(start)
            if let end { return "\(startFormatted)-\(formatTimeString(end))" }
            return startFormatted
        } ?? ""
        return "\(uniqueDays.joined(separator: "/")) \(time)"
    }

    private func shortDayLabel(_ day: String) -> String {
        switch day.lowercased().prefix(3) {
        case "mon": return "Mon"
        case "tue": return "Tue"
        case "wed": return "Wed"
        case "thu": return "Thu"
        case "fri": return "Fri"
        case "sat": return "Sat"
        case "sun": return "Sun"
        default: return day
        }
    }

    private func formatTimeString(_ time: String) -> String {
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let min = Int(parts[1]) else { return time }
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let suffix = hour >= 12 ? "PM" : "AM"
        return min == 0 ? "\(h12) \(suffix)" : "\(h12):\(String(format: "%02d", min)) \(suffix)"
    }

    // MARK: - Interim Voice Bar

    private var interimVoiceBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundColor(.red)
                .font(.caption)
            Text(interimVoiceText)
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.vertical, 6)
        .background(NoteVConfig.Design.surface)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Voice input
            ChatVoiceInput(
                onTextRecognized: { text in
                    inputText = text
                    interimVoiceText = ""
                    sendMessage()
                },
                onInterimUpdate: { text in
                    interimVoiceText = text
                }
            )

            // Text field
            TextField(isHomeChat ? "Type or speak..." : "Ask about this lecture...",
                      text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundColor(NoteVConfig.Design.textPrimary)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NoteVConfig.Design.surface)
                .cornerRadius(20)
                .onSubmit { sendMessage() }

            // Image picker
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 3, matching: .images) {
                Image(systemName: pendingImages.isEmpty ? "paperclip" : "paperclip.circle.fill")
                    .font(.title3)
                    .foregroundColor(pendingImages.isEmpty ? NoteVConfig.Design.textSecondary : NoteVConfig.Design.accent)
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task { await loadSelectedPhotos(newItems) }
            }

            // Send button
            Button(action: { sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSend ? NoteVConfig.Design.accent : NoteVConfig.Design.textSecondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.vertical, 8)
        .background(NoteVConfig.Design.background)
    }

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespaces).isEmpty || !pendingImages.isEmpty)
            && !chatService.isLoading
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty || !pendingImages.isEmpty else { return }

        let messageText = text.isEmpty ? "Here's an image" : text
        let images = pendingImages

        inputText = ""
        pendingImages = []
        selectedPhotos = []

        chatService.activeSendTask = Task {
            await chatService.sendMessage(messageText, images: images)
        }
    }

    private func startNewChat() {
        let conversation = ChatStore.shared.createConversation()
        chatService.switchConversation(to: conversation.id)
        clearInputState()
    }

    private func clearInputState() {
        inputText = ""
        interimVoiceText = ""
        pendingImages = []
        selectedPhotos = []
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        await MainActor.run {
            pendingImages = loaded
        }
    }

    // MARK: - Markdown Rendering

    private func markdownAttributedString(_ text: String, foregroundColor: Color) -> AttributedString {
        do {
            var result = try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            result.foregroundColor = foregroundColor
            return result
        } catch {
            var fallback = AttributedString(text)
            fallback.foregroundColor = foregroundColor
            return fallback
        }
    }
}
