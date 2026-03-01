# NoteV

**AI classroom assistant for Meta Ray-Ban smart glasses.**

> Every AI note-taker can hear. Ours can see.

NoteV captures audio + visual content during lectures via Meta Ray-Ban Gen-2 smart glasses (or iPhone camera fallback), then generates structured multimodal notes with AI-powered transcript polishing, slide analysis, and action item extraction.

## Architecture

```
Capture Layer       → CaptureProvider protocol (Glasses or Phone)
                       ↓ timestamped frames + audio
Processing Layer    → AudioPipeline (Deepgram / Apple Speech STT)
                    → FramePipeline (sampling + change detection)
                    → SmartBookmarkDetector (auto-detect key moments)
                    → SessionRecorder (orchestrator → SessionData)
                       ↓
Generation Layer    → TranscriptPolisher (chunked LLM → PolishedTranscript)
                    → SlideAnalyzer (LLM vision → slide content extraction)
                    → NoteGenerator (multimodal LLM → StructuredNotes)
                    → TodoExtractor (text-only LLM → [TodoItem])
                       ↓
Presentation        → SessionResultView (3 tabs: Timeline + AI Notes + Tasks)
                    → UnifiedChatService (AI chat for Q&A, course setup, settings)
                    → WeeklyScheduleSheet (iOS Calendar-style course view)
```

## Tech Stack

- **Platform**: iOS 17+ / Swift 6 / SwiftUI / Xcode 15+
- **Hardware**: Meta Ray-Ban Gen-2 (DAT SDK v0.4.0) with iPhone camera fallback
- **STT**: Deepgram nova-3 (primary) / Apple Speech (fallback)
- **LLM**: OpenAI GPT-4o / Anthropic Claude / Google Gemini (configurable)
- **Storage**: FileManager + JSON + JPEG (no CoreData)

## Features

### Recording & Processing
- **Dual capture**: Meta Ray-Ban glasses via DAT SDK or iPhone back camera
- **Real-time STT**: Deepgram WebSocket streaming with KeepAlive and graceful shutdown
- **Smart bookmarks**: Auto-detect "this will be on the exam", "important", etc. via 4-tier keyword taxonomy
- **Frame intelligence**: 5s sampling + pixel-difference change detection + pHash slide deduplication

### Three-Layer Output
- **Layer 1 — Polished Timeline**: AI-cleaned transcript with inline images and bookmark highlights
- **Layer 2 — AI Notes**: Structured notes organized by slide transitions with timestamps
- **Layer 3 — Action Items**: Extracted TODOs with categories, priorities, due dates → iOS Reminders export

### AI Chat System
- **Unified chat**: Q&A about notes, course setup, settings config, reminders — all via natural language
- **Voice input**: Deepgram-powered with 5s utterance timeout
- **Action cards**: Confirmable UI cards for add courses, change settings, create reminders
- **Session context**: Chat can access transcript, notes, slides, and todos for the current session

### Course Management
- **Conversational setup**: Tell AI your schedule naturally ("I have CS229 MWF 10am")
- **Auto-detection**: Automatically detects current course when recording starts
- **Weekly calendar**: iOS Calendar-style grid with course blocks, red NOW line, today highlight
- **Duplicate prevention**: Won't re-add courses with same name and schedule

## Build & Run

```bash
# Open in Xcode
open NoteV.xcodeproj

# Build from CLI
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project NoteV.xcodeproj -scheme NoteV \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Configuration

1. **LLM**: Tap gear icon → select provider (Gemini / OpenAI / Anthropic) → enter API key
2. **Deepgram**: API key configured in `APIKeys.swift` for voice STT
3. **Courses**: Chat with NoteV → tell it your schedule → confirm action card

Or configure everything through the AI chat: "Set my API key to sk-..."

## Design System

| Token | Value |
|-------|-------|
| Background | `#0D1117` |
| Surface | `#161B22` |
| Accent | `#00E5FF` |
| Bookmark | `#FF6B35` |
| Font | SF Pro (system) |

## License

Proprietary. All rights reserved.
