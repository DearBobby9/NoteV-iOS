import Foundation

// MARK: - SessionStore

/// Persists and retrieves session data using FileManager + JSON.
/// TODO: Phase 2 — Full persistence implementation
final class SessionStore {

    // MARK: - Properties

    private let fileManager = FileManager.default

    private var sessionsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(NoteVConfig.Storage.sessionsDirectory)
    }

    // MARK: - Init

    init() {
        NSLog("[SessionStore] Initialized — directory: \(sessionsDirectory.path)")
        ensureDirectoryExists()
    }

    // MARK: - Directory Setup

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: sessionsDirectory.path) {
            do {
                try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
                NSLog("[SessionStore] Created sessions directory")
            } catch {
                NSLog("[SessionStore] ERROR creating directory: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Save

    /// Save a session to disk.
    func save(session: SessionData) throws {
        NSLog("[SessionStore] save() called — session: \(session.id)")
        // TODO: Phase 2
        // 1. Create session subdirectory
        // 2. Encode SessionData as JSON
        // 3. Write JSON to session directory
        // 4. Frame images stored separately via ImageStore
        let sessionDir = sessionsDirectory.appendingPathComponent(session.id.uuidString)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(session)
        try data.write(to: sessionDir.appendingPathComponent("session.json"))

        NSLog("[SessionStore] Session saved: \(session.id)")
    }

    // MARK: - Load

    /// Load a session from disk by ID.
    func load(sessionId: UUID) throws -> SessionData {
        NSLog("[SessionStore] load() called — session: \(sessionId)")
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId.uuidString)
        let data = try Data(contentsOf: sessionDir.appendingPathComponent("session.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionData.self, from: data)
    }

    /// List all saved sessions (metadata only).
    func listSessions() -> [SessionMetadata] {
        NSLog("[SessionStore] listSessions() called")
        // TODO: Phase 2 — Scan sessions directory and load metadata
        return []
    }

    // MARK: - Delete

    /// Delete a session from disk.
    func delete(sessionId: UUID) throws {
        NSLog("[SessionStore] delete() called — session: \(sessionId)")
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId.uuidString)
        try fileManager.removeItem(at: sessionDir)
    }
}
