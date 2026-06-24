import AVFoundation
import XCTest
@testable import NoteV

final class VideoPipelineTests: XCTestCase {

    // MARK: - PTS Conversion

    func testSessionTimestampFromPresentationTime() {
        let start = CMTime(seconds: 10.0, preferredTimescale: 600)
        let pts = CMTime(seconds: 15.5, preferredTimescale: 600)

        let sessionTime = VisualSampleProcessor.sessionTimestamp(
            presentationTime: pts,
            sessionStart: start
        )

        XCTAssertEqual(sessionTime, 5.5, accuracy: 0.001)
    }

    func testEstablishTimebaseAlignsAudioAndVideo() {
        let processor = VisualSampleProcessor()
        let videoPTS = CMTime(seconds: 100.0, preferredTimescale: 600)
        let audioPTS = CMTime(seconds: 102.25, preferredTimescale: 600)

        let videoBuffer = makeSampleBuffer(presentationTime: videoPTS, mediaType: .video)
        let audioBuffer = makeSampleBuffer(presentationTime: audioPTS, mediaType: .audio)

        processor.processVideoSample(videoBuffer)
        let audioTimestamp = processor.establishTimebaseIfNeeded(for: audioBuffer)

        XCTAssertEqual(audioTimestamp, 2.25, accuracy: 0.001)
    }

    // MARK: - SessionMetadata videoFilename

    func testSessionDataCodableRoundTripWithVideoFilename() throws {
        let metadata = SessionMetadata(
            captureSource: .phone,
            title: "Video Session",
            videoFilename: NoteVConfig.Storage.sessionVideoFilename
        )

        let session = SessionData(metadata: metadata)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionData.self, from: data)

        XCTAssertEqual(decoded.metadata.videoFilename, NoteVConfig.Storage.sessionVideoFilename)
    }

    // MARK: - VideoRecorder lifecycle

    func testVideoRecorderFinishWithoutFramesReturnsNil() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notev-test-\(UUID().uuidString).mp4")

        let recorder = VideoRecorder()
        try recorder.startRecording(to: tempURL)

        let result = try await recorder.finishRecording()
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testVideoRecorderRejectsDoubleStart() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notev-test-\(UUID().uuidString).mp4")

        let recorder = VideoRecorder()
        try recorder.startRecording(to: tempURL)

        do {
            try recorder.startRecording(to: tempURL)
            XCTFail("Expected alreadyRecording error")
        } catch let error as VideoRecorder.VideoRecorderError {
            XCTAssertEqual(error.errorDescription, "Video recording already in progress")
        }
    }

    // MARK: - SessionStore

    func testSessionStoreVideoURL() {
        let store = SessionStore()
        let sessionId = UUID()
        let url = store.videoURL(for: sessionId)

        XCTAssertTrue(url.lastPathComponent == NoteVConfig.Storage.sessionVideoFilename)
        XCTAssertTrue(url.path.contains(sessionId.uuidString))
    }

    // MARK: - Helpers

    private func makeSampleBuffer(presentationTime: CMTime, mediaType: AVMediaType) -> CMSampleBuffer {
        var formatDescription: CMFormatDescription?
        if mediaType == .video {
            CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCVPixelFormatType_32BGRA,
                width: 64,
                height: 64,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        } else {
            var asbd = AudioStreamBasicDescription(
                mSampleRate: 44100,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 2,
                mFramesPerPacket: 1,
                mBytesPerFrame: 2,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 16,
                mReserved: 0
            )
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            )
        }

        guard let formatDescription else {
            fatalError("Failed to create format description")
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let sampleBuffer else {
            fatalError("Failed to create sample buffer")
        }
        return sampleBuffer
    }
}
