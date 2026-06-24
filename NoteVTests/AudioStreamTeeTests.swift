import XCTest
@testable import NoteV

final class AudioStreamTeeTests: XCTestCase {

    func testTeeDeliversSameChunksToBothStreams() async {
        let source = AsyncStream<AudioChunk> { continuation in
            continuation.yield(AudioChunk(timestamp: 0, data: Data([0, 1]), duration: 0.1))
            continuation.yield(AudioChunk(timestamp: 1, data: Data([2, 3]), duration: 0.1))
            continuation.finish()
        }

        let (stt, mux) = AudioStreamTee.tee(source)

        var sttChunks: [AudioChunk] = []
        var muxChunks: [AudioChunk] = []

        async let sttCollect: Void = {
            for await chunk in stt { sttChunks.append(chunk) }
        }()
        async let muxCollect: Void = {
            for await chunk in mux { muxChunks.append(chunk) }
        }()

        _ = await (sttCollect, muxCollect)

        XCTAssertEqual(sttChunks.count, 2)
        XCTAssertEqual(muxChunks.count, 2)
        XCTAssertEqual(sttChunks[0].timestamp, muxChunks[0].timestamp)
        XCTAssertEqual(sttChunks[1].data, muxChunks[1].data)
    }
}
