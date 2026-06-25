---
date: 2026-06-24
topic: post-processing-pipeline
---

# Post-Recording Processing Pipeline

## What We're Building

A clear **post-recording processing experience** for NoteV now that sessions capture full MP4 video alongside sparse live frames. During recording, the app keeps **live Deepgram transcription** and **sparse live frame previews** (current `VisualSampleProcessor` fan-out). After the user stops recording, a **staged processing pipeline** runs with visible progress (spinner/steps), and the user can **fully reprocess** the session from the saved MP4 + transcript.

The core insight: **you do not need to rewrite the AI pipeline.** `SlideAnalyzer`, `NoteGenerator`, `TranscriptPolisher`, and `TodoExtractor` already run post-stop and consume JPEG frames + transcript text — not MP4. The main architectural addition is a **post-stop frame enrichment step** that extracts additional frames from `session.mp4` using transcript density and visual change detection, then feeds the existing downstream pipeline. This controls API costs while improving quality during fast-moving lectures.

## Why This Approach

Three approaches were considered:

### A. MP4-Only Capture, Extract Everything Post-Stop

Record MP4 + live STT only. All analysis frames extracted after stop via `AVAssetImageGenerator` + change detection.

- Pros: Simplest capture path; zero duplicate JPEG work during recording; API budget applied only post-stop
- Cons: No live thumbnails/frame count during recording — conflicts with chosen UX
- Best when: Live visual feedback is not required

### B. Keep Live Fan-Out As-Is, No Post Enrichment

Continue using throttled live JPEGs as the sole input to `SlideAnalyzer` / `NoteGenerator`. MP4 is replay-only.

- Pros: Minimal change; pipeline already works on branch
- Cons: Misses denser frames when lecture accelerates; 5s throttle may under-sample fast slide changes; no adaptive cost/quality knob
- Best when: Ship fast, accept current analysis quality

### C. Hybrid — Live Preview + Post-Stop Authoritative Extraction (Recommended)

During recording: keep sparse live fan-out for UI (thumbnails, frame count, burst on change). After stop: run a **Frame Extraction Pass** on `session.mp4` that produces the **authoritative frame set** for AI — adaptive density driven by transcript windows and visual scene changes. Live JPEGs remain a preview cache; post-stop frames supersede them for analysis.

- Pros: Live UX preserved; better quality when lecture is dense; API costs bounded by post-stop extraction budget + existing pHash dedup; existing LLM pipeline unchanged
- Cons: Extra processing time after stop; need timestamp alignment between MP4 PTS and transcript; full retry must re-run extraction
- Best when: Balanced cost, quality, and UX (user's stated goal)

**Chosen: Approach C**

## Key Decisions

- **Keep live Deepgram STT during recording.** Audio transcription is the one API call that must be live; it already feeds the post-stop pipeline. No change to `AudioPipeline` contract.

- **Keep sparse live frame fan-out during recording.** `VisualSampleProcessor` continues throttled JPEG yield (5s periodic, 1s burst) for live UI. Do not remove this path.

- **Add post-stop Frame Extraction Pass from MP4.** New step after `SessionRecorder.stopRecording()` saves `session.mp4`. Uses `AVAssetImageGenerator` to seek/extract at:
  - Base periodic intervals (e.g. every 5s)
  - Transcript-dense windows (high words/minute → tighter sampling)
  - Visual scene-change timestamps (re-run change detection on extracted samples or scan MP4 at coarser intervals first)

- **Post-stop frames are authoritative for AI.** `SlideAnalyzer` and `NoteGenerator` consume the enriched frame set written to `ImageStore`, not the sparse live preview JPEGs. Live frames can be replaced or merged with dedup.

- **Do not send MP4 to LLM.** Vision API calls remain per-JPEG, bounded by `pHash` dedup (`FrameDeduplicator`) and `maxUniqueSlides` (40). Extraction budget caps raw candidates before vision calls.

- **Unified PostProcessingOrchestrator with staged progress.** Replace ad-hoc `Task` chains in `LiveSessionView` / `SessionResultView` with a single orchestrator exposing stages:
  1. Finalizing session (save MP4, dedupe transcript)
  2. Extracting frames from video
  3. Polishing transcript
  4. Analyzing slides
  5. Generating notes
  6. Extracting todos

  UI shows spinner + current stage label. Failures are stage-scoped with retry.

- **Full reprocess on retry.** User-selected: retry reruns extraction from MP4 through all LLM steps. Requires session artifacts on disk (`session.mp4`, `session.json`, transcript).

- **API cost controls (no pipeline rewrite).**
  - Extraction budget: max candidate frames per session (e.g. 200–300 before dedup)
  - Adaptive density: only tighten sampling in transcript-dense or visually-changing windows
  - Existing `pHash` dedup before vision LLM calls
  - Existing `maxFramesInPrompt = 20` cap on NoteGenerator multimodal input
  - SlideAnalyzer concurrency limit (3) unchanged

- **Timestamp alignment.** Frame extraction seeks use MP4 PTS aligned to session time zero (same as `VisualSampleProcessor`). Transcript segment `startTime` maps to extraction windows. Glasses audio wall-clock drift accepted in v1 with documented ±500ms tolerance.

## Processing Flow (Target)

```
RECORDING (live)
├── Deepgram STT → transcript segments (API: audio duration)
├── VisualSampleProcessor → sparse JPEGs (UI only) + full MP4
└── Smart bookmarks (local, no API)

STOP → save session.mp4 + session.json

POST-PROCESSING (staged, spinner)
├── Stage 1: Finalize / validate artifacts
├── Stage 2: Extract frames from MP4 (adaptive: transcript density + scene change)
│            → write authoritative JPEGs to ImageStore
├── Stage 3: TranscriptPolisher (text LLM, chunked)
├── Stage 4: SlideAnalyzer (vision LLM per unique slide, pHash dedup)
├── Stage 5: NoteGenerator (1 multimodal LLM call)
└── Stage 6: TodoExtractor (1 text LLM call)

RETRY / REPROCESS
└── Re-run Stage 2–6 from disk (session.mp4 + saved transcript)
```

## What Stays the Same

- `FramePipeline` change detection logic (can be reused in post-stop scan)
- `SlideAnalyzer`, `NoteGenerator`, `TranscriptPolisher`, `TodoExtractor` contracts
- `SessionData` + `ImageStore` on-disk layout
- MP4 for Video tab playback only (not LLM input)
- Live bookmark via `capturePhoto()` (supplement, not replace extraction)

## What Changes

| Area | Change |
|------|--------|
| New | `FrameExtractor` / `SessionFrameExtractor` — MP4 → JPEG at adaptive timestamps |
| New | `PostProcessingOrchestrator` — staged pipeline with progress + retry |
| New | Transcript-density analyzer for adaptive extraction windows |
| UI | Post-stop spinner with stage labels; "Reprocess" button on `SessionResultView` |
| UI | Fix `retryGeneration()` to include slide analysis + frame re-extraction (current gap) |
| `LiveSessionView` | Delegate post-stop work to orchestrator instead of inline Task chain |
| Config | Extraction budget, density thresholds, stage enable flags |

## Open Questions

- **Extraction budget:** What max candidate frames per 60-min session? (Proposal: 250 pre-dedup, ~40 post-dedup vision calls unchanged)
- **Live vs authoritative merge:** Replace live JPEGs entirely post-stop, or keep both and dedup? (Lean: replace — simpler, one source of truth)
- **Processing location:** Run extraction on-device only, or optional cloud offload later? (v1: on-device)
- **Partial failure UX:** If slide analysis fails but notes succeed, can user retry slides only despite full-reprocess preference? (Plan phase: consider step-scoped retry as v1.1)
- **Backfill:** Reprocess sessions recorded before MP4 existed? (Out of scope — no MP4 on disk)
- **Glasses timestamp drift:** Does adaptive transcript-window extraction need glasses audio PTS fix first? (Evaluate on device)

## Success Criteria

- User sees clear post-recording progress (stage + spinner) after every session
- Full reprocess from MP4 + transcript works without re-recording
- API costs do not increase vs today for a typical 60-min lecture (bounded extraction + existing dedup)
- Note/slide quality improves or matches baseline on fast-slide lecture fixtures
- Live recording UX unchanged (transcript + sparse thumbnails during capture)
