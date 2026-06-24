import Foundation

// MARK: - ExtractionTimestampPlanner

/// Builds a deduplicated, budget-capped list of session-relative seek times for MP4 frame extraction.
enum ExtractionTimestampPlanner {

    static func planTimestamps(
        duration: TimeInterval,
        denseWindows: [ClosedRange<TimeInterval>],
        sceneChangeTimes: [TimeInterval],
        baseInterval: TimeInterval = NoteVConfig.FrameExtraction.baseSamplingInterval,
        denseInterval: TimeInterval = NoteVConfig.FrameExtraction.denseWindowMinInterval,
        maxCandidates: Int = NoteVConfig.FrameExtraction.maxCandidateFrames,
        mergeTolerance: TimeInterval = 0.5
    ) -> [TimeInterval] {
        guard duration > 0 else { return [0] }

        var timestamps: [TimeInterval] = [0]

        var anchor = baseInterval
        while anchor <= duration {
            timestamps.append(anchor)
            anchor += baseInterval
        }

        for window in denseWindows {
            var t = window.lowerBound
            while t <= window.upperBound {
                timestamps.append(t)
                t += denseInterval
            }
        }

        timestamps.append(contentsOf: sceneChangeTimes.filter { $0 >= 0 && $0 <= duration })
        timestamps.sort()

        var merged: [TimeInterval] = []
        for time in timestamps {
            if let last = merged.last, time - last < mergeTolerance {
                continue
            }
            merged.append(time)
        }

        if merged.count <= maxCandidates {
            return merged
        }

        return prioritize(maxCandidates: maxCandidates, candidates: merged, sceneChangeTimes: sceneChangeTimes)
    }

    // MARK: - Private

    private static func prioritize(
        maxCandidates: Int,
        candidates: [TimeInterval],
        sceneChangeTimes: [TimeInterval]
    ) -> [TimeInterval] {
        let sceneSet = Set(sceneChangeTimes.map { ( $0 * 10 ).rounded() / 10 })
        var selected = candidates.filter { sceneSet.contains(($0 * 10).rounded() / 10) }

        for time in candidates where selected.count < maxCandidates {
            if !selected.contains(where: { abs($0 - time) < 0.5 }) {
                selected.append(time)
            }
        }

        return Array(selected.prefix(maxCandidates)).sorted()
    }
}
