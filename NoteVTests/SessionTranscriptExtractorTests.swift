import XCTest
@testable import NoteV

final class SessionTranscriptExtractorTests: XCTestCase {

    func testParseUtterancesResponse() throws {
        let json = """
        {
          "results": {
            "channels": [{ "alternatives": [{ "transcript": "Hello world", "words": [] }] }],
            "utterances": [
              { "start": 0.5, "end": 2.1, "transcript": "Hello world" },
              { "start": 2.5, "end": 4.0, "transcript": "Second phrase" }
            ]
          }
        }
        """.data(using: .utf8)!

        let segments = try SessionTranscriptExtractor.parseSegments(from: json)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "Hello world")
        XCTAssertEqual(segments[0].startTime, 0.5, accuracy: 0.01)
        XCTAssertTrue(segments[0].isFinal)
        XCTAssertEqual(segments[1].text, "Second phrase")
    }

    func testParseWordsFallbackGroupsByPause() throws {
        let json = """
        {
          "results": {
            "channels": [{
              "alternatives": [{
                "transcript": "One two three four",
                "words": [
                  { "word": "One", "start": 0.0, "end": 0.2 },
                  { "word": "two", "start": 0.3, "end": 0.5 },
                  { "word": "three", "start": 2.0, "end": 2.2 },
                  { "word": "four", "start": 2.3, "end": 2.5 }
                ]
              }]
            }]
          }
        }
        """.data(using: .utf8)!

        let segments = try SessionTranscriptExtractor.parseSegments(from: json)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "One two")
        XCTAssertEqual(segments[1].text, "three four")
    }

    func testTranscriptExtractionEnabled() {
        XCTAssertTrue(NoteVConfig.TranscriptExtraction.enabled)
    }

    func testDeepgramMetadataTimeoutAllowsLTE() {
        XCTAssertGreaterThanOrEqual(NoteVConfig.Audio.deepgramMetadataTimeoutSeconds, 25)
    }

    func testValidateAudioPayloadRejectsSmallExport() {
        XCTAssertThrowsError(try SessionTranscriptExtractor.validateAudioPayload(
            data: Data(repeating: 0, count: 144),
            audioDuration: 20,
            videoDuration: 20
        ))
    }

    func testValidateAudioPayloadAcceptsHealthyExport() throws {
        try SessionTranscriptExtractor.validateAudioPayload(
            data: Data(repeating: 0, count: 4096),
            audioDuration: 18,
            videoDuration: 20
        )
    }

    func testReferenceDurationIgnoresCorruptContainerVideoDuration() {
        let reference = SessionTranscriptExtractor.referenceDurationForValidation(
            audioDuration: 9.7,
            containerVideoDuration: 74_586
        )
        XCTAssertEqual(reference, 9.7, accuracy: 0.01)
    }

    func testValidateAudioPayloadAcceptsWhenContainerDurationInflated() throws {
        try SessionTranscriptExtractor.validateAudioPayload(
            data: Data(repeating: 0, count: 4096),
            audioDuration: 9.7,
            videoDuration: 74_586
        )
    }

    func testWrapPCMAsWAVProducesValidHeader() {
        let pcm = Data(repeating: 0, count: 3200)
        let wav = SessionTranscriptExtractor.wrapPCMAsWAV(pcmData: pcm, sampleRate: 16_000, channels: 1)
        XCTAssertGreaterThanOrEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }
}
