import Foundation

// MARK: - ChatMessage

/// A single message in a chat conversation.
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var imageAttachments: [String]?   // filenames of attached images (stored in chat directory)
    var actionPayload: ActionPayload? // structured action for confirm/cancel UI

    enum ChatRole: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        imageAttachments: [String]? = nil,
        actionPayload: ActionPayload? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.imageAttachments = imageAttachments
        self.actionPayload = actionPayload
    }

    // Exclude isStreaming from persistence — always false on load
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, imageAttachments, actionPayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isStreaming = false
        imageAttachments = try container.decodeIfPresent([String].self, forKey: .imageAttachments)
        actionPayload = try container.decodeIfPresent(ActionPayload.self, forKey: .actionPayload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(imageAttachments, forKey: .imageAttachments)
        try container.encodeIfPresent(actionPayload, forKey: .actionPayload)
    }
}

// MARK: - ActionPayload

/// Structured action data embedded in assistant messages for confirm/cancel UI.
struct ActionPayload: Codable, Sendable {
    let type: ActionType
    let data: String   // JSON string of action-specific data
    var status: ActionStatus

    enum ActionType: String, Codable, Sendable {
        case addCourses
        case setSetting
        case createReminder
    }

    enum ActionStatus: String, Codable, Sendable {
        case pending
        case confirmed
        case cancelled
    }
}
