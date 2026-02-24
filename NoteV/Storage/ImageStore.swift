import Foundation
import UIKit

// MARK: - ImageStore

/// Persists and retrieves frame images as JPEG files.
/// TODO: Phase 2 — Full implementation with thumbnail generation
final class ImageStore {

    // MARK: - Properties

    private let fileManager = FileManager.default

    private var sessionsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(NoteVConfig.Storage.sessionsDirectory)
    }

    // MARK: - Init

    init() {
        NSLog("[ImageStore] Initialized")
    }

    // MARK: - Save

    /// Save image data as a JPEG file for a given session.
    func saveImage(_ imageData: Data, filename: String, sessionId: UUID) throws {
        NSLog("[ImageStore] saveImage() called — filename: \(filename), session: \(sessionId)")
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId.uuidString)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let filePath = sessionDir.appendingPathComponent(filename)
        try imageData.write(to: filePath)

        NSLog("[ImageStore] Image saved: \(filePath.lastPathComponent)")
    }

    // MARK: - Load

    /// Load image data for a given session and filename.
    func loadImage(filename: String, sessionId: UUID) -> Data? {
        let filePath = sessionsDirectory
            .appendingPathComponent(sessionId.uuidString)
            .appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: filePath.path) else {
            NSLog("[ImageStore] Image not found: \(filename)")
            return nil
        }

        return try? Data(contentsOf: filePath)
    }

    // MARK: - Compress

    /// Compress raw image data to JPEG at configured quality.
    func compressToJPEG(_ imageData: Data) -> Data? {
        guard let uiImage = UIImage(data: imageData) else {
            NSLog("[ImageStore] ERROR: Could not create UIImage from data")
            return nil
        }
        return uiImage.jpegData(compressionQuality: NoteVConfig.Storage.jpegCompressionQuality)
    }
}
