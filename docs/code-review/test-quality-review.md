# Test Quality Review

**Scope:** Capture-resilience work — `CaptureResilienceTests`, `VideoPipelineTests`, `PostProcessingOrchestratorTests`, `MarkdownRendererTests`, and implementations for `SessionRecorder` checkpoint/flush, `NoteGenerator` chunked merge, `VideoRecorder` pending buffers, `BackgroundTaskCoordinator`.

**Date:** 2026-06-24

---

## Coverage Summary

| Metric | Result |
|--------|--------|
| Test run | **Pass** — 48/48 tests (`xcodebuild test`, iPhone 17 / iOS 26.5) |
| Overall coverage | Not enforced by CI; spot-check on changed files below |
| Files with meaningful tests for this feature | **2/7** |

### File-level coverage (changed/resilience code)

| File | Coverage | Tests exist? |
|------|----------|--------------|
| `SessionData+Capture.swift` | 72% | Partial — `filtered`, `canReprocess` only |
| `VisualSampleProcessor.swift` | 59% | Yes — `flushAndWait` exercised indirectly |
| `VideoRecorder.swift` | 86% | Partial — happy-path mux only |
| `SessionRecorder.swift` | **2.7%** | **No** |
| `NoteGenerator.swift` | **0%** | **No** |
| `BackgroundTaskCoordinator.swift` | **0%** | **No** |
| `PostProcessingOrchestrator.swift` | **3.8%** | Label/flag tests only |

### Missing test files (critical)

| Implementation | Status |
|----------------|--------|
| `NoteV/Processing/SessionRecorder.swift` — `saveRecordingCheckpoint()`, `flushRecordingPipeline()`, `startCheckpointTask()` | **No test file** |
| `NoteV/NoteGeneration/NoteGenerator.swift` — `generateNotesInChunks()` merge | **No test file** |
| `NoteV/Utilities/BackgroundTaskCoordinator.swift` | **No test file** |
| `NoteV/Processing/VideoRecorder.swift` — pending-audio buffer paths | Partial — gaps below |

---

## State Management Test Quality

### `CaptureResilienceTests.swift` — Issues found

Tests config helpers and `SessionData` extensions only. They do **not** exercise recording resilience behavior.

- `testSessionFilteredToTimeRange` — **Pass** — validates chunk input slicing used by note generation.
- `testCanReprocessWhenVideoFilenamePresent` — **Pass** — single happy path; does not cover `hasRecoverableArtifacts(videoExistsOnDisk:)`.
- **Gap:** No tests for checkpoint persistence, periodic flush, or pipeline drain on background/disconnect.

### `PostProcessingOrchestratorTests.swift` — Issues found

All four tests assert static strings and boolean flags. None invoke `scheduleProcessing`, `process`, or `BackgroundTaskCoordinator.run`.

- **Gap:** Post-processing orchestration — including background task wrapping — is completely untested.
- **Gap:** `hasRecoverableArtifacts` early-exit at `.finalizing` is untested.

### `SessionRecorder` (no test file) — **Critical gaps**

Implementation under test (`SessionRecorder.swift`):

```603:658:NoteV/Processing/SessionRecorder.swift
    func flushRecordingPipeline() async {
        guard isRecording else { return }
        await captureManager?.flushPendingSamples()
        await visualSampleProcessor?.flushAndWait()
        ...
    }

    func saveRecordingCheckpoint() {
        guard isRecording, let sessionId, let sessionStartTime else { return }
        ...
        try sessionStore.save(session: checkpoint)
    }

    private func startCheckpointTask() {
        checkpointTask = Task { [weak self] in
            ...
            await self?.flushRecordingPipeline()
            self?.saveRecordingCheckpoint()
        }
    }
```

**Missing tests (critical):**

1. **`saveRecordingCheckpoint` writes recoverable partial session**
   - Persists via `SessionStore` with `title: "Recording in progress"`, `endDate: nil`, correct `durationSeconds`.
   - Sets `videoFilename` when `videoRecorder != nil`.
   - Strips `imageData` from frames before save.
   - Applies `deduplicateSegments` to transcript (not raw collector buffer).
   - No-op when `!isRecording`.

2. **`flushRecordingPipeline` drains in-flight samples**
   - Calls `captureManager.flushPendingSamples()` and `visualSampleProcessor.flushAndWait()` when recording.
   - No-op when `!isRecording`.
   - Invoked from `LiveSessionView` on background and from checkpoint task — regressions would lose transcript/video on crash or route change.

3. **`startCheckpointTask` periodic behavior**
   - Fires on `NoteVConfig.LongSession.recordingCheckpointIntervalSeconds` (30s).
   - Each tick: flush then checkpoint (ordering matters for MP4 integrity).
   - Cancels cleanly in `stopRecording()`.

`SessionRecorder` is `@MainActor` and tightly coupled to `CaptureManager`; tests will need injected fakes for `CaptureManager`, `SessionStore`, and optionally `VisualSampleProcessor`/`VideoRecorder`, or extraction of checkpoint assembly into a pure helper.

---

## Service / Pipeline Test Quality

### `NoteGenerator` chunked merge (no test file) — **Critical gap**

`generateNotes()` routes sessions over 3600s to `generateNotesInChunks()`:

```68:140:NoteV/NoteGeneration/NoteGenerator.swift
    private func generateNotesInChunks(from session: SessionData) async throws -> StructuredNotes {
        ...
        if chunkIndex == 0 {
            mergedTitle = chunkNotes.title
            mergedSummary = chunkNotes.summary
        } else if !chunkNotes.summary.isEmpty {
            mergedSummary += mergedSummary.isEmpty ? chunkNotes.summary : " " + chunkNotes.summary
        }
        for takeaway in chunkNotes.keyTakeaways where !mergedTakeaways.contains(takeaway) {
            mergedTakeaways.append(takeaway)
        }
        for section in chunkNotes.sections.sorted(by: { $0.order < $1.order }) {
            mergedSections.append(NoteSection(..., order: sectionOrder, ...))
            sectionOrder += 1
        }
        ...
    }
```

**Missing tests (critical):**

1. **Threshold routing** — session at 3601s uses chunked path; session at 3599s uses single pass.
2. **Chunk count** — 5400s session → 3 chunks (1800s each per `noteChunkDurationSeconds`).
3. **Merge semantics:**
   - Title from chunk 0 only.
   - Summary concatenation with space separator across chunks.
   - Key takeaways deduplicated (same string in two chunks appears once).
   - Section `order` renumbered globally (0…N), not per-chunk.
4. **Chunk input** — each LLM call receives `session.filtered(to:)` slice (frames/segments in range only).

`NoteGenerator` already accepts injected `promptBuilder`, `llmService`, `noteParser` — a stub `LLMService` returning deterministic markdown per chunk is sufficient. **Zero tests exist today.**

### `VideoPipelineTests.swift` — Partial pass, critical gaps on pending buffers

**What passes:**

- `testProcessorFlushAndWaitBeforeFinishRecording` — covers `VisualSampleProcessor.flushAndWait()` → `VideoRecorder.waitForPendingAppends()`.
- `testVideoRecorderMuxesAudioTrack` — video-then-audio happy path; 1 audio sample muxed.

**Critical gaps in `VideoRecorder` pending-audio logic:**

```155:224:NoteV/Processing/VideoRecorder.swift
    if mediaType == .audio, videoInput == nil {
        pendingAudioBuffers.append(sampleBuffer)
        trimPendingAudioBuffersIfNeeded()
        return
    }
    ...
    guard input.isReadyForMoreMediaData else {
        if mediaType == .audio {
            pendingAudioBuffers.append(sampleBuffer)
            trimPendingAudioBuffersIfNeeded()
            ...
        }
        return
    }
    ...
    private func flushPendingAudioBuffers() throws { ... }
    private func trimPendingAudioBuffersIfNeeded() { ... }
```

| Scenario | Tested? | Risk |
|----------|---------|------|
| Audio arrives **before** first video frame | **No** | Early audio dropped or session start misaligned |
| Audio appended when input **not ready** (back-pressure queue) | **No** | Samples lost under load |
| `flushPendingAudioBuffers` on `finishRecording` after queue buildup | **No** | Truncated audio in MP4 |
| `trimPendingAudioBuffersIfNeeded` overflow (> `maxPendingAudioBuffers`) | **No** | Memory pressure / silent sample drop |
| Session start PTS uses earliest pending audio timestamp | **No** | A/V sync drift |

**Recommended tests:**

- `testVideoRecorderBuffersAudioBeforeVideoThenFlushesOnFirstVideo` — append audio at t=0, video at t=0.1; assert `muxedAudioSampleCount >= 1` and audio track present.
- `testVideoRecorderFlushesPendingAudioOnFinish` — queue audio-only samples, then video, finish; assert all queued samples muxed.
- `testVideoRecorderTrimsOverflowPendingBuffers` — inject >2400 pending buffers (or lower config in test); assert count capped.

---

## UI Component Test Quality

### `MarkdownRendererTests.swift` — Pass

Five tests cover bold, lists, inline-only whitespace, empty input, and plain-text fallback. Assertions verify rendered output and presentation intents — not tautological. **Adequate for renderer scope; not related to capture resilience.**

---

## Anti-Patterns Found

| Location | Anti-pattern | Issue | Fix |
|----------|--------------|-------|-----|
| `PostProcessingOrchestratorTests.swift` | **Missing state tests** | Only display-name/flag assertions; orchestration and background wrapping untested | Add tests for `process()` stage transitions with stubbed dependencies |
| `CaptureResilienceTests.swift` | **False confidence naming** | File name implies resilience coverage; tests only config + `SessionData` helpers | Rename or add real `SessionRecorder` resilience tests |
| `VideoPipelineTests.swift:216-248` | **Happy-path-only mux** | Audio-after-video passes; audio-before-video and back-pressure paths never exercised | Add adversarial buffer-order tests above |
| *(entire suite)* | **Untested crash-recovery contract** | Checkpoint + flush are the core resilience guarantee with zero verification | Highest-priority additions |

No tautological assertions or empty-expectation tests found in scoped files.

---

## Recommendations

Priority order for **critical gaps only**:

1. **`SessionRecorder` checkpoint + flush tests** — highest user impact (data loss on crash/background). Verify persisted JSON shape, deduped transcript, stripped frame blobs, and flush-before-save ordering.
2. **`NoteGenerator` chunked merge tests** — inject stub LLM returning distinct markdown per chunk; assert merged title/summary/takeaways/section order for a >3600s synthetic session.
3. **`VideoRecorder` pending-audio buffer tests** — audio-before-video, back-pressure queue, flush-on-finish, overflow trim.
4. **`BackgroundTaskCoordinator` test** — verify `beginBackgroundTask`/`endBackgroundTask` called (swizzle or protocol wrapper); assert operation result propagates and task ID cleared in defer.
5. **`PostProcessingOrchestrator.scheduleProcessing`** — smoke test that processing runs inside coordinator wrapper (can use fast no-op `process` stub).

### Suggested test file additions

| New file | Covers |
|----------|--------|
| `NoteVTests/SessionRecorderResilienceTests.swift` | `saveRecordingCheckpoint`, `flushRecordingPipeline`, checkpoint task lifecycle |
| `NoteVTests/NoteGeneratorChunkedTests.swift` | `generateNotesInChunks` merge + threshold routing |
| `NoteVTests/BackgroundTaskCoordinatorTests.swift` | Background task lifecycle |
| Extend `VideoPipelineTests.swift` | Pending audio buffer adversarial cases |

---

## Verdict

**Fix 4 critical gaps before merging** the capture-resilience feature.

| Severity | Count | Items |
|----------|-------|-------|
| **Critical** | 4 | No checkpoint tests; no `flushRecordingPipeline` tests; no chunked note merge tests; no `BackgroundTaskCoordinator` tests |
| Important | 1 | `VideoRecorder` pending-audio adversarial paths untested (86% line coverage masks untested branches) |

Existing tests pass and cover adjacent helpers (`SessionData.filtered`, `VisualSampleProcessor.flushAndWait`, basic video mux), but the **resilience guarantees this PR adds are unverified**. A regression in checkpoint timing, flush ordering, or chunk merge would ship silently.
