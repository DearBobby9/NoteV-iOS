import Foundation

// MARK: - TranscriptDensityAnalyzer

/// Identifies transcript time windows with high speech density for tighter frame extraction.
struct TranscriptDensityAnalyzer {

    /// Returns session-relative time ranges where words-per-minute exceeds the configured threshold.
    func denseWindows(
        segments: [TranscriptSegment],
        sessionDuration: TimeInterval,
        windowSize: TimeInterval = 30,
        wpmThreshold: Double = NoteVConfig.FrameExtraction.denseWordsPerMinuteThreshold
    ) -> [ClosedRange<TimeInterval>] {
        guard sessionDuration > 0, !segments.isEmpty else { return [] }

        let meaningful = segments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.startTime < $1.startTime }

        guard !meaningful.isEmpty else { return [] }

        var windows: [ClosedRange<TimeInterval>] = []
        var windowStart: TimeInterval = 0

        while windowStart < sessionDuration {
            let windowEnd = min(windowStart + windowSize, sessionDuration)
            let range = windowStart...windowEnd
            let wordCount = wordCount(in: meaningful, within: range)
            let minutes = max((windowEnd - windowStart) / 60.0, 1.0 / 60.0)
            let wpm = Double(wordCount) / minutes

            if wpm >= wpmThreshold {
                windows.append(range)
            }
            windowStart += windowSize
        }

        return mergeAdjacent(windows)
    }

    // MARK: - Private

    private func wordCount(in segments: [TranscriptSegment], within range: ClosedRange<TimeInterval>) -> Int {
        segments.reduce(0) { total, segment in
            guard segment.startTime >= range.lowerBound, segment.startTime < range.upperBound else {
                return total
            }
            let words = segment.text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return total + words.count
        }
    }

    private func mergeAdjacent(_ windows: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
        guard var merged = windows.sorted(by: { $0.lowerBound < $1.lowerBound }).first.map({ [$0] }) ?? [] else {
            return []
        }

        for window in windows.dropFirst() {
            if let last = merged.last, window.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                merged.append(window)
            }
        }
        return merged
    }
}
