# Test Quality Review

**Scope:** LTE Deepgram reconnect, live STT failure UX, MP4 transcript recovery  
**Branch context:** `hotfix/deepgram-lte-mp4-transcript-fallback` (uncommitted)  
**Changed test files:** `SessionTranscriptExtractorTests.swift`, `PostProcessingOrchestratorTests.swift`  
**Review date:** 2026-06-24

---

## Test Quality Review

### Coverage Summary

- **Test run:** Pass — 36 tests, 0 failures (`xcodebuild test -scheme NoteV -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`)
- **Coverage:** 10.27% app target (2199/21421 lines); no project threshold configured
- **Key file coverage (app target):**

| File | Coverage | Notes |
|------|----------|-------|
| `SessionTranscriptExtractor.swift` | 31.79% (103/324) | Static helpers exercised; async `extract(from:)` / AVFoundation paths untested |
| `PostProcessingOrchestrator.swift` | 4.80% (11/229) | Only enum/display wiring hit indirectly; `.recoveringTranscript` stage logic untested |
| `AudioPipeline.swift` | 0.00% (0/561) | All Deepgram reconnect logic uncovered |
| `DeepgramService.swift` | 0.00% (0/389) | `sendAudio` Bool return, Metadata wait, connection-lost paths uncovered |
| `LiveTranscriptStatus.swift` | N/A | Enum-only; no executable code to cover |

- **Files with tests:** 5/5 test files in `NoteVTests/` (project has no dedicated tests for services/processing added in this hotfix)
- **Missing test files:**

| Path | Gap |
|------|-----|
| `NoteV/Processing/AudioPipeline.swift` | No `AudioPipelineTests.swift` — mid-session reconnect, buffer flush, status callbacks |
| `NoteV/Services/DeepgramService.swift` | No `DeepgramServiceTests.swift` — `sendAudio` success/failure, Metadata timeout, disconnect |
| `NoteV/Processing/PostProcessingOrchestrator.swift` | Existing tests cover labels only; no orchestration/recovery behavior tests |
| `NoteV/Models/LiveTranscriptStatus.swift` | No tests (low priority — pure enum) |
| `NoteV/Views/LiveSessionView.swift` | No UI tests for live transcript warning/hint states |

---

### State Management Test Quality

This project uses `AppState` + `SessionRecorder` as `@MainActor` / `ObservableObject` coordinators (not Bloc). Live STT state spans `liveTranscriptStatus`, `liveTranscriptHint`, and `liveTranscriptWarning`.

- **`PostProcessingOrchestratorTests.swift`:** Issues found
  - Tests verify `PostProcessingStage.recoveringTranscript.displayName`, `SessionStatus.recoveringTranscript.isPostProcessing`, and related flags — useful smoke checks.
  - **Missing:** No test that empty `transcriptSegments` + existing `session.mp4` triggers `SessionTranscriptExtractor.extract`, populates segments, and clears the "Live transcription unavailable" warning.
  - **Missing:** No test for recovery failure path (warning appended, pipeline continues).
  - **Missing:** No test for `fromStage: .recoveringTranscript` reprocess entry point used by `SessionResultView`.

- **`AppState` / `SessionRecorder` live STT wiring:** No tests
  - `SessionRecorder` maps `AudioPipeline.onLiveTranscriptStatusChange` to `AppState.liveTranscriptStatus` and hint/warning strings — untested state transitions (`.connecting` → `.streaming` → `.unavailable`).

---

### Service / Processing Test Quality

- **`SessionTranscriptExtractorTests.swift`:** Pass (partial)
  - **Strong:** `parseSegments` (utterances + word-grouping fallback), `validateAudioPayload` byte threshold, `wrapPCMAsWAV` header structure — behavior-focused, good fixtures.
  - **Gap:** `validateAudioPayload` duration-ratio rejection (`minAudioDurationRatio`) not tested despite being core to corrupt M4A detection.
  - **Gap:** `extract(from:)` integration (M4A → PCM/WAV → full MP4 fallback chain) untested — requires AVFoundation fixtures or injected session mock.
  - **Weak:** Config smoke tests (see Anti-Patterns).

- **`AudioPipeline.swift` (no test file):** Critical gap
  - Mid-session reconnect (`attemptMidSessionReconnect`, `connectDeepgramWithRetry`, `resetBridge`) is the highest-risk new logic and has **zero** automated coverage.
  - Scenarios that must be tested:
    1. Initial connect succeeds → pending chunks flushed, bridge started.
    2. `sendAudio` returns `false` → reconnect attempted → chunk retried on success.
    3. Reconnect exhausts `deepgramMidSessionReconnectMax` → `.unavailable` reported, feed continues without live STT.
    4. Reconnect calls `coordinator.resetBridge()` → transcript bridge task restarted (regression guard for one-shot `markBridgeStarted` bug).
    5. `activateDeepgramService` returns `false` when buffered flush send fails.

- **`DeepgramService.swift` (no test file):** Critical gap
  - `sendAudio(_:) async -> Bool` is the new contract driving reconnect; untested paths:
    - Returns `false` when `!isConnected` or `webSocketTask == nil`.
    - Returns `false` on send error and invokes `handleConnectionLost`.
    - Returns `true` on successful send.
  - `waitForMetadataReady` LTE tolerance (poll after transient errors) untested.
  - Recommend `URLProtocol` stub or injectable WebSocket factory — actor isolation requires `@testable` access or protocol extraction.

---

### UI Component Test Quality

- **`LiveSessionView` / `TranscriptScrollView`:** No tests
  - Live transcript warning renders in both banner (`LiveSessionView`) and inline placeholder (`TranscriptScrollView`) — duplicate UX untested.
  - No snapshot or ViewInspector tests for `.connecting` / `.streaming` / `.unavailable` presentation.
  - Acceptable deferral for hotfix **only if** AudioPipeline status tests exist; currently neither layer is covered.

---

### Anti-Patterns Found

- **`SessionTranscriptExtractorTests.swift:52-54`** — Config constant assertion
  - Issue: `testTranscriptExtractionEnabled` asserts `NoteVConfig.TranscriptExtraction.enabled == true`. Tests compile-time config, not behavior; breaks if config is intentionally toggled off in test target.
  - Fix: Remove or gate behind `#if DEBUG` fixture; assert behavior in orchestrator test when enabled vs disabled.

- **`SessionTranscriptExtractorTests.swift:56-58`** — Config threshold assertion
  - Issue: `testDeepgramMetadataTimeoutAllowsLTE` checks `deepgramMetadataTimeoutSeconds >= 25` — documents intent but does not verify Metadata wait behavior in `DeepgramService`.
  - Fix: Replace with unit test that Metadata arrives within timeout (mock) or times out and throws.

- **`PostProcessingOrchestratorTests.swift:30-32`** — Config constant assertion
  - Issue: `testSessionVideoFilenameMatchesStorageConfig` duplicates knowledge already in `NoteVConfig`.
  - Fix: Use filename in an orchestrator/recovery test that constructs `sessionStore.videoURL(for:)`.

- **`PostProcessingOrchestratorTests.swift` (overall)** — Label-only tests for orchestrator
  - Issue: Tests verify display strings and boolean flags but not the staged pipeline the hotfix depends on. Creates false confidence that recovery is tested.
  - Fix: Add `@MainActor` test with mocked `SessionTranscriptExtractor` / temp session directory.

---

### Pattern Compliance

| Pattern | Status | Notes |
|---------|--------|-------|
| XCTest + `@testable import NoteV` | ✅ | Consistent across all test files |
| Static helper extraction for testability | ✅ | `SessionTranscriptExtractor.validateAudioPayload`, `parseSegments`, `wrapPCMAsWAV` |
| `setUp`/`tearDown` for shared fixtures | ⚠️ | Not used in changed files; acceptable for pure static tests |
| Group organization (`// MARK:`) | ✅ | Present in older tests; changed files use flat structure (minor) |
| Mocking / dependency injection | ❌ | No mocks for `DeepgramService`, `URLSession`, or `SessionStore` in orchestrator |
| Async test waiting | ✅ | `VideoPipelineTests` demonstrates proper `Task` + sleep patterns; not applied to new async paths |

---

### Recommendations

1. **Add `AudioPipelineTests.swift` with injectable Deepgram factory** — highest impact. Extract or protocol-wrap `DeepgramService` creation so tests can simulate connect failure, send failure, and reconnect success without network. Assert `onLiveTranscriptStatusChange` sequence.

2. **Add `DeepgramServiceTests.swift` using `URLProtocol`** — stub WebSocket handshake and verify `sendAudio` Bool return, Metadata gating, and connection-lost handling.

3. **Add orchestrator recovery test** — temp directory + stub MP4 + mock extractor returning segments; assert `updatedSession.transcriptSegments` populated and warning removed.

4. **Add `testValidateAudioPayloadRejectsShortAudioTrack`** — audio duration below 50% of video duration throws (already flagged in VGV review).

5. **Remove or downgrade config-only tests** — replace with behavior tests tied to the feature.

6. **Optional: extract `DeepgramFeedCoordinator` to internal testable type** — enables direct tests for buffer cap (`deepgramConnectBufferMaxChunks`) and `resetBridge()` without full pipeline.

---

### Verdict

**Fix 3 critical coverage gaps before merging.**

The MP4 recovery **parsing/validation helpers** are well tested, but the **live LTE reconnect path** (`AudioPipeline` + `DeepgramService.sendAudio`) and **post-stop recovery orchestration** (`PostProcessingOrchestrator.recoveringTranscript`) — the two P0 workstreams — have no meaningful automated tests. Existing additions to `PostProcessingOrchestratorTests` and config smoke tests in `SessionTranscriptExtractorTests` do not compensate for that gap.

---

## Issue Counts

| Severity | Count |
|----------|-------|
| Critical | 3 |
| Important | 5 |
| Suggestions | 4 |

### Critical (one-line)

1. **`AudioPipeline` reconnect logic — 0% coverage; no test file for mid-session reconnect, bridge reset, or status callbacks.**
2. **`DeepgramService.sendAudio` Bool contract — 0% coverage; disconnected and send-failure paths untested.**
3. **`PostProcessingOrchestrator.recoveringTranscript` stage — no behavior test; only display-name/flag smoke tests added.**

### Important (one-line)

1. **`validateAudioPayload` duration-ratio edge case not tested** (short audio vs video length).
2. **`SessionTranscriptExtractor.extract(from:)` async path untested** (M4A/PCM/MP4 fallback chain).
3. **`SessionRecorder` → `AppState` live STT status mapping untested.**
4. **Config constant tests** (`testTranscriptExtractionEnabled`, `testDeepgramMetadataTimeoutAllowsLTE`, `testSessionVideoFilenameMatchesStorageConfig`) assert constants, not behavior.
5. **No UI tests** for live transcript warning/hint in `LiveSessionView` / `TranscriptScrollView`.

### Suggestions (one-line)

1. Extract `DeepgramFeedCoordinator` for isolated buffer/bridge unit tests.
2. Consolidate live STT UI state tests around `LiveTranscriptStatus` enum transitions.
3. Add `#if DEBUG` test hooks or factory injection on `PostProcessingOrchestrator` for stage-level testing.
4. Enable CI coverage reporting with a minimum threshold on `Processing/` and `Services/` directories.
