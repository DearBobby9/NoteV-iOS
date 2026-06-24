import AVFoundation
import XCTest
@testable import NoteV

final class SessionFrameExtractorTests: XCTestCase {

    func testExtractionTimestampPlannerPeriodicAnchors() {
        let timestamps = ExtractionTimestampPlanner.planTimestamps(
            duration: 12,
            denseWindows: [],
            sceneChangeTimes: []
        )
        XCTAssertEqual(timestamps, [0, 5, 10])
    }

    func testExtractionTimestampPlannerDenseWindowAddsSamples() {
        let timestamps = ExtractionTimestampPlanner.planTimestamps(
            duration: 10,
            denseWindows: [4...8],
            sceneChangeTimes: [],
            baseInterval: 5,
            denseInterval: 1,
            maxCandidates: 250,
            mergeTolerance: 0.5
        )
        XCTAssertTrue(timestamps.contains(0))
        XCTAssertTrue(timestamps.contains(5))
        XCTAssertTrue(timestamps.contains(4))
        XCTAssertTrue(timestamps.contains(7))
    }

    func testExtractionTimestampPlannerRespectsBudget() {
        let timestamps = ExtractionTimestampPlanner.planTimestamps(
            duration: 600,
            denseWindows: [],
            sceneChangeTimes: [],
            baseInterval: 1,
            denseInterval: 1,
            maxCandidates: 20,
            mergeTolerance: 0.1
        )
        XCTAssertLessThanOrEqual(timestamps.count, 20)
    }

    func testTranscriptDensityAnalyzerFindsDenseWindow() {
        let analyzer = TranscriptDensityAnalyzer()
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 4, text: "one two three four five six seven eight nine ten", isFinal: true),
            TranscriptSegment(startTime: 5, endTime: 9, text: "eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty", isFinal: true),
            TranscriptSegment(startTime: 35, endTime: 36, text: "twentyone", isFinal: true)
        ]

        let windows = analyzer.denseWindows(segments: segments, sessionDuration: 60, windowSize: 30, wpmThreshold: 20)
        XCTAssertFalse(windows.isEmpty)
        XCTAssertEqual(windows.first?.lowerBound, 0)
    }

    func testFrameChangeDetectorIdenticalImagesScoreZero() {
        let gray = [UInt8](repeating: 128, count: 64 * 64)
        XCTAssertEqual(FrameChangeDetector.pixelDifference(imageA: gray, imageB: gray), 0, accuracy: 0.001)
    }

    func testFrameChangeDetectorDifferentImagesScoreHigh() {
        let a = [UInt8](repeating: 0, count: 64 * 64)
        let b = [UInt8](repeating: 255, count: 64 * 64)
        XCTAssertGreaterThan(FrameChangeDetector.pixelDifference(imageA: a, imageB: b), 0.9)
    }

    func testSessionFrameExtractorFromSyntheticMP4() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notev-extract-\(UUID().uuidString).mp4")
        let sessionId = UUID()

        let recorder = VideoRecorder()
        try recorder.startRecording(to: tempURL)
        let buffer = makeVideoSampleBuffer(presentationTime: CMTime(seconds: 0, preferredTimescale: 600))
        recorder.appendVideo(buffer)
        try await Task.sleep(nanoseconds: 200_000_000)
        _ = try await recorder.finishRecording()

        let session = SessionData(
            metadata: SessionMetadata(sessionId: sessionId, durationSeconds: 1, videoFilename: "session.mp4"),
            frames: [
                TimestampedFrame(timestamp: 0, trigger: .periodic, imageFilename: "frame_0001.jpg"),
                TimestampedFrame(timestamp: 2, trigger: .bookmark, imageFilename: "bookmark_1.jpg")
            ],
            transcriptSegments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "hello world", isFinal: true)
            ]
        )

        let extractor = SessionFrameExtractor()
        let updated = try await extractor.extract(session: session, videoURL: tempURL)

        XCTAssertFalse(updated.frames.isEmpty)
        XCTAssertTrue(updated.frames.contains(where: { $0.imageFilename == "bookmark_1.jpg" }))
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Helpers

    private func makeVideoSampleBuffer(presentationTime: CMTime) -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey as String: true] as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { fatalError("pixel buffer") }

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { fatalError("format") }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { fatalError("sample buffer") }
        return sampleBuffer
    }
}
