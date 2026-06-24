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
}
