import AVFoundation
import Foundation
import UIKit

// MARK: - SessionFrameExtractor

/// Extracts authoritative analysis frames from a session MP4 after recording stops.
final class SessionFrameExtractor {

    enum ExtractionError: Error, LocalizedError {
        case videoUnreadable
        case noFramesExtracted

        var errorDescription: String? {
            switch self {
            case .videoUnreadable: return "Could not read session video for frame extraction"
            case .noFramesExtracted: return "No frames could be extracted from session video"
            }
        }
    }

    private let imageStore: ImageStore
    private let densityAnalyzer: TranscriptDensityAnalyzer

    init(imageStore: ImageStore = ImageStore(), densityAnalyzer: TranscriptDensityAnalyzer = TranscriptDensityAnalyzer()) {
        self.imageStore = imageStore
        self.densityAnalyzer = densityAnalyzer
    }

    /// Replace periodic live-preview frames with MP4-extracted JPEGs; preserve bookmark images.
    func extract(session: SessionData, videoURL: URL) async throws -> SessionData {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw ExtractionError.videoUnreadable
        }

        let bookmarkFrames = session.frames.filter { $0.imageFilename.hasPrefix("bookmark_") }
        let denseWindows = densityAnalyzer.denseWindows(
            segments: session.transcriptSegments,
            sessionDuration: duration
        )

        let extraction = try await Task.detached(priority: .userInitiated) { [self] in
            try await self.extractOnBackground(
                asset: asset,
                duration: duration,
                denseWindows: denseWindows
            )
        }.value

        guard !extraction.frames.isEmpty else {
            throw ExtractionError.noFramesExtracted
        }

        try imageStore.deletePeriodicFrameImages(sessionId: session.id, preserving: bookmarkFrames.map(\.imageFilename))

        var updated = session
        for frame in extraction.frames {
            if let data = frame.imageData {
                try imageStore.saveImage(data, filename: frame.imageFilename, sessionId: session.id)
            }
        }

        var storedFrames = extraction.frames.map { frame -> TimestampedFrame in
            var copy = frame
            copy.imageData = nil
            return copy
        }
        storedFrames.append(contentsOf: bookmarkFrames)
        storedFrames.sort { $0.timestamp < $1.timestamp }
        updated.frames = storedFrames

        NSLog("[SessionFrameExtractor] Extracted \(extraction.frames.count) frames — \(extraction.sceneChanges) scene changes, \(denseWindows.count) dense windows")
        return updated
    }

    // MARK: - Background work

    private struct BackgroundExtraction {
        let frames: [TimestampedFrame]
        let sceneChanges: Int
    }

    private func extractOnBackground(
        asset: AVURLAsset,
        duration: TimeInterval,
        denseWindows: [ClosedRange<TimeInterval>]
    ) async throws -> BackgroundExtraction {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sceneChanges = try await detectSceneChanges(
            duration: duration,
            generator: generator
        )

        let timestamps = ExtractionTimestampPlanner.planTimestamps(
            duration: duration,
            denseWindows: denseWindows,
            sceneChangeTimes: sceneChanges,
            baseInterval: NoteVConfig.FrameExtraction.adaptiveBaseInterval(forDuration: duration)
        )

        var frames: [TimestampedFrame] = []
        frames.reserveCapacity(timestamps.count)

        for (index, timestamp) in timestamps.enumerated() {
            let cmTime = CMTime(seconds: timestamp, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
            guard let jpegData = UIImage(cgImage: cgImage).jpegData(
                compressionQuality: NoteVConfig.Storage.jpegCompressionQuality
            ) else {
                continue
            }

            let filename = String(format: "frame_%04d.jpg", index + 1)
            frames.append(
                TimestampedFrame(
                    timestamp: timestamp,
                    trigger: .periodic,
                    changeScore: 0,
                    imageFilename: filename,
                    imageData: jpegData
                )
            )
        }

        return BackgroundExtraction(frames: frames, sceneChanges: sceneChanges.count)
    }

    private func detectSceneChanges(
        duration: TimeInterval,
        generator: AVAssetImageGenerator
    ) async throws -> [TimeInterval] {
        var changes: [TimeInterval] = []
        var previousGray: [UInt8]?
        let interval = NoteVConfig.FrameExtraction.coarseScanInterval
        var time: TimeInterval = 0

        while time <= duration {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
            if let gray = FrameChangeDetector.grayscale(from: cgImage) {
                if let previous = previousGray {
                    let diff = FrameChangeDetector.pixelDifference(imageA: previous, imageB: gray)
                    if diff > NoteVConfig.Frame.changeDetectionThreshold {
                        changes.append(time)
                    }
                }
                previousGray = gray
            }
            time += interval
        }

        return changes
    }
}

private extension CMTime {
    var seconds: TimeInterval {
        CMTimeGetSeconds(self)
    }
}
