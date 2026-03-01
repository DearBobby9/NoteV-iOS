import Foundation

// MARK: - ChatConversation

/// Lightweight metadata for a chat conversation (stored in index, not full messages).
struct ChatConversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var lastMessageAt: Date
    var messageCount: Int
    var isSessionChat: Bool  // true = tied to a recording session, excluded from home history
}

// MARK: - ChatStore

/// JSON file persistence for chat conversations. One file per conversation.
/// Maintains a conversations index for listing without loading all messages.
@MainActor
final class ChatStore {

    static let shared = ChatStore()

    private let fileManager = FileManager.default

    private var chatsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("NoteVChats", isDirectory: true)
    }

    private var indexURL: URL {
        chatsDirectory.appendingPathComponent("_conversations.json")
    }

    /// In-memory cache of conversation index
    private var conversationsCache: [ChatConversation]?

    private init() {
        try? fileManager.createDirectory(at: chatsDirectory, withIntermediateDirectories: true)
        migrateHomeChatIfNeeded()
        NSLog("[ChatStore] Initialized — directory: \(chatsDirectory.path)")
    }

    // MARK: - Conversation Index

    /// List all home conversations (excludes session chats), sorted by lastMessageAt descending.
    func listConversations() -> [ChatConversation] {
        let all = loadIndex()
        return all
            .filter { !$0.isSessionChat }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// Create a new conversation and return its metadata.
    func createConversation(title: String = "New Chat", isSessionChat: Bool = false) -> ChatConversation {
        let conversation = ChatConversation(
            id: UUID(),
            title: title,
            createdAt: Date(),
            lastMessageAt: Date(),
            messageCount: 0,
            isSessionChat: isSessionChat
        )
        var index = loadIndex()
        index.append(conversation)
        saveIndex(index)
        NSLog("[ChatStore] Created conversation: \(conversation.id.uuidString.prefix(8)) — '\(title)'")
        return conversation
    }

    /// Get the most recent home conversation, or nil if none exist.
    func mostRecentConversation() -> ChatConversation? {
        listConversations().first
    }

    /// Get or create: returns the most recent conversation, or creates a new one.
    func getOrCreateConversation() -> ChatConversation {
        if let recent = mostRecentConversation() {
            return recent
        }
        return createConversation()
    }

    // MARK: - File Path

    private func fileURL(for conversationId: UUID) -> URL {
        chatsDirectory.appendingPathComponent("\(conversationId.uuidString).json")
    }

    // MARK: - Load

    func loadConversation(id: UUID) -> [ChatMessage] {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            NSLog("[ChatStore] Loaded \(messages.count) messages for conversation \(id.uuidString.prefix(8))")
            return messages
        } catch {
            NSLog("[ChatStore] Failed to load conversation \(id.uuidString.prefix(8)): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Save

    func saveConversation(id: UUID, messages: [ChatMessage]) {
        let url = fileURL(for: id)
        let persistable = messages.filter { !$0.isStreaming }

        do {
            let data = try JSONEncoder().encode(persistable)
            try data.write(to: url, options: .atomic)
            NSLog("[ChatStore] Saved \(persistable.count) messages for conversation \(id.uuidString.prefix(8))")
        } catch {
            NSLog("[ChatStore] Failed to save conversation \(id.uuidString.prefix(8)): \(error.localizedDescription)")
        }

        // Update index metadata
        updateConversationMeta(id: id, messages: persistable)
    }

    // MARK: - Append

    func appendMessage(conversationId: UUID, message: ChatMessage) {
        var messages = loadConversation(id: conversationId)
        messages.append(message)
        saveConversation(id: conversationId, messages: messages)
    }

    // MARK: - Delete

    func deleteConversation(id: UUID) {
        let url = fileURL(for: id)
        try? fileManager.removeItem(at: url)

        // Also delete image directory
        let imgDir = imageDirectory(for: id)
        try? fileManager.removeItem(at: imgDir)

        // Remove from index
        var index = loadIndex()
        index.removeAll { $0.id == id }
        saveIndex(index)

        NSLog("[ChatStore] Deleted conversation \(id.uuidString.prefix(8))")
    }

    // MARK: - Image Storage

    private func imageDirectory(for conversationId: UUID) -> URL {
        chatsDirectory.appendingPathComponent(conversationId.uuidString, isDirectory: true)
    }

    func saveImage(_ data: Data, conversationId: UUID, filename: String) {
        let dir = imageDirectory(for: conversationId)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try? data.write(to: url)
    }

    func loadImage(conversationId: UUID, filename: String) -> Data? {
        let url = imageDirectory(for: conversationId).appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    // MARK: - Index Management (Private)

    private func loadIndex() -> [ChatConversation] {
        if let cached = conversationsCache { return cached }

        guard fileManager.fileExists(atPath: indexURL.path) else {
            conversationsCache = []
            return []
        }

        do {
            let data = try Data(contentsOf: indexURL)
            let conversations = try JSONDecoder().decode([ChatConversation].self, from: data)
            conversationsCache = conversations
            return conversations
        } catch {
            NSLog("[ChatStore] Failed to load index: \(error.localizedDescription)")
            conversationsCache = []
            return []
        }
    }

    private func saveIndex(_ conversations: [ChatConversation]) {
        conversationsCache = conversations
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("[ChatStore] Failed to save index: \(error.localizedDescription)")
        }
    }

    private func updateConversationMeta(id: UUID, messages: [ChatMessage]) {
        var index = loadIndex()

        guard let i = index.firstIndex(where: { $0.id == id }) else {
            // Not in index (e.g. session chats) — skip
            return
        }

        index[i].messageCount = messages.count
        index[i].lastMessageAt = messages.last?.timestamp ?? index[i].lastMessageAt

        // Auto-title from first user message if still default
        if index[i].title == "New Chat",
           let firstUserMsg = messages.first(where: { $0.role == .user }) {
            let raw = firstUserMsg.content.prefix(40)
            if firstUserMsg.content.count > 40, let lastSpace = raw.lastIndex(of: " ") {
                index[i].title = String(raw[raw.startIndex..<lastSpace]) + "..."
            } else {
                index[i].title = String(raw)
            }
        }

        saveIndex(index)
    }

    // MARK: - Migration

    /// Migrate legacy homeChatID conversation into the new index system.
    private func migrateHomeChatIfNeeded() {
        let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let legacyURL = fileURL(for: legacyID)

        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        // Check if already in index
        let index = loadIndex()
        if index.contains(where: { $0.id == legacyID }) { return }

        // Load legacy messages to build metadata
        let messages = loadConversation(id: legacyID)
        guard !messages.isEmpty else { return }

        let title = messages.first(where: { $0.role == .user })
            .map { String($0.content.prefix(40)) } ?? "Chat"

        let conversation = ChatConversation(
            id: legacyID,
            title: title,
            createdAt: messages.first?.timestamp ?? Date(),
            lastMessageAt: messages.last?.timestamp ?? Date(),
            messageCount: messages.count,
            isSessionChat: false
        )

        var updated = index
        updated.append(conversation)
        saveIndex(updated)

        NSLog("[ChatStore] Migrated legacy home chat into index — \(messages.count) messages")
    }
}
