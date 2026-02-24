import Foundation

// MARK: - SessionStore

/// Persists and retrieves session data using FileManager + JSON.
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
        let sessionDir = sessionsDirectory.appendingPathComponent(session.id.uuidString)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(session)
        try data.write(to: sessionDir.appendingPathComponent("session.json"))

        NSLog("[SessionStore] Session saved: \(session.id) (\(data.count) bytes)")
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

    /// List all saved sessions sorted by date (newest first).
    func listSessions() -> [SessionMetadata] {
        NSLog("[SessionStore] listSessions() called")

        guard let contents = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            NSLog("[SessionStore] No sessions found or error reading directory")
            return []
        }

        var metadata: [SessionMetadata] = []

        for dir in contents {
            let sessionFile = dir.appendingPathComponent("session.json")
            guard fileManager.fileExists(atPath: sessionFile.path) else { continue }

            do {
                let data = try Data(contentsOf: sessionFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let session = try decoder.decode(SessionData.self, from: data)
                metadata.append(session.metadata)
            } catch {
                NSLog("[SessionStore] ERROR loading session from \(dir.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Sort by start date, newest first
        metadata.sort { $0.startDate > $1.startDate }
        NSLog("[SessionStore] Found \(metadata.count) sessions")
        return metadata
    }

    /// Load all sessions (full data) sorted by date (newest first).
    func loadAllSessions() -> [SessionData] {
        NSLog("[SessionStore] loadAllSessions() called")

        guard let contents = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var sessions: [SessionData] = []

        for dir in contents {
            let sessionFile = dir.appendingPathComponent("session.json")
            guard fileManager.fileExists(atPath: sessionFile.path) else { continue }

            do {
                let data = try Data(contentsOf: sessionFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let session = try decoder.decode(SessionData.self, from: data)
                sessions.append(session)
            } catch {
                NSLog("[SessionStore] ERROR loading session: \(error.localizedDescription)")
            }
        }

        sessions.sort { $0.metadata.startDate > $1.metadata.startDate }
        return sessions
    }

    // MARK: - Delete

    /// Delete a session from disk.
    func delete(sessionId: UUID) throws {
        NSLog("[SessionStore] delete() called — session: \(sessionId)")
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId.uuidString)
        try fileManager.removeItem(at: sessionDir)
    }
}
