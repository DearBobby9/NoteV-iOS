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
                    → TodayScheduleSheet (iOS Calendar-style course view)
```

## Tech Stack

- **Platform**: iOS 17+ / Swift 6 / SwiftUI / Xcode 15+
- **Hardware**: Meta Ray-Ban Gen-2 (DAT SDK v0.4.0) with iPhone camera fallback
- **STT**: Deepgram nova-3 via native `URLSessionWebSocketTask` (primary) / Apple Speech (fallback)
- **LLM**: OpenAI GPT-4o / Anthropic Claude / Google Gemini (configurable in-app)
- **Native Frameworks**: EventKit (Reminders & Calendar export), PDFKit (PDF generation), Speech (on-device STT)
- **Storage**: FileManager + JSON + JPEG (no CoreData)

## Features

### Recording & Processing
- **Dual capture**: Meta Ray-Ban glasses via DAT SDK or iPhone back camera
- **Real-time STT**: Deepgram WebSocket streaming with KeepAlive and graceful shutdown
- **Smart bookmarks**: Auto-detect "this will be on the exam", "important", etc. via 4-tier keyword taxonomy with confidence scoring
- **Frame intelligence**: 5s periodic sampling + SSIM change detection + pHash slide deduplication

### Three-Layer Output
- **Layer 1 — Polished Timeline**: AI-cleaned transcript with inline images, bookmark highlights, and sticky section headers
- **Layer 2 — AI Notes**: Structured notes organized by slide transitions with timestamps and TOC navigation
- **Layer 3 — Action Items**: Extracted TODOs with categories, priorities, due dates → export to iOS Reminders/Calendar via Export Preview Sheet

### Export & Sharing
- **Export Preview Sheet**: Review and edit action items before batch export — toggle Reminder vs Calendar Event, edit titles, dates, and priorities
- **PDF Export**: Generate formatted PDF with inline images and section timestamps
- **iOS Reminders Integration**: Batch export to dedicated "NoteV Tasks" list with deep links back to session timestamps

### AI Chat System
- **Unified chat**: Q&A about notes, course setup, settings config, reminders — all via natural language
- **Voice input**: Deepgram-powered dictation with 5s utterance timeout (separate `DeepgramVoiceService` optimized for short-form input)
- **Action cards**: Confirmable UI cards for adding courses, changing settings, creating reminders
- **Session context**: Chat accesses transcript, notes, slides, and todos for the current session
- **Persistent history**: Conversations saved across sessions via `ChatStore`

### Course Management
- **Conversational setup**: Tell AI your schedule naturally ("I have CS229 MWF 10am")
- **Auto-detection**: Automatically detects current course when recording starts based on schedule
- **Weekly calendar**: iOS Calendar-style grid with course blocks, red NOW line, today highlight
- **Post-recording prompt**: Bottom sheet to manually assign course if auto-detection fails
- **Duplicate prevention**: Won't re-add courses with same name and schedule

## Project Structure

```
NoteV/
├── NoteV.xcodeproj/
├── NoteV/
│   ├── App/              # NoteVApp entry point, AppState (session lifecycle)
│   ├── Capture/          # CaptureProvider protocol, CaptureManager, Glasses + Phone providers
│   ├── Config/           # NoteVConfig (all tunable params), Config.xcconfig, Info.plist
│   ├── Models/           # SessionData, TranscriptSegment, Bookmark, TodoItem, Course, etc.
│   ├── NoteGeneration/   # NoteGenerator, PromptBuilder, TranscriptPolisher, TodoExtractor, PDFGenerator
│   ├── Processing/       # AudioPipeline, FramePipeline, SessionRecorder, SmartBookmarkDetector, SlideAnalyzer
│   ├── Services/         # LLMService, DeepgramService, DeepgramVoiceService, ReminderSyncService, APIKeys
│   ├── Settings/         # SettingsManager (UserDefaults persistence)
│   ├── Storage/          # SessionStore, CourseStore, ChatStore, ImageStore (JSON + JPEG)
│   └── Views/
│       ├── StartSessionView, LiveSessionView, SessionResultView, SessionListView, ...
│       └── Components/   # ChatView, TranscriptTimelineView, TimelineNoteView, TasksTabView,
│                         # ExportPreviewSheet, TodayScheduleSheet, ChatVoiceInput, ...
└── NoteVTests/
```

## Prerequisites

- **Xcode 15+** (Swift 6 concurrency support required)
- **iOS 17+** deployment target
- **Deepgram API key** for real-time speech-to-text — [Get one here](https://console.deepgram.com/)
- **LLM API key** (at least one): [OpenAI](https://platform.openai.com/api-keys) / [Anthropic](https://console.anthropic.com/) / [Google Gemini](https://aistudio.google.com/apikey)
- **Meta Ray-Ban Gen-2** glasses (optional — iPhone camera fallback works in simulator)
- Physical iPhone required for glasses features (DAT SDK does not run in simulator)

## Getting Started

```bash
# 1. Clone
git clone https://github.com/DearBobby9/NoteV-iOS.git
cd NoteV-iOS

# 2. Configure API keys
cp NoteV/Config/Secrets.xcconfig.example NoteV/Config/Secrets.xcconfig
# Edit NoteV/Config/Secrets.xcconfig — add your Deepgram API key

# 3. Open in Xcode
open NoteV.xcodeproj
# Set your signing team in Xcode → NoteV target → Signing & Capabilities

# 4. Build & run
# In Xcode: select iPhone simulator or physical device → Cmd+R
```

### CLI Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project NoteV.xcodeproj -scheme NoteV \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

> Note: `DEVELOPER_DIR` is required if `xcode-select` points to CommandLineTools instead of Xcode.app.

## Configuration

### API Keys (via xcconfig)

API keys are injected through Xcode build settings, not hardcoded in source:

1. Copy `NoteV/Config/Secrets.xcconfig.example` → `NoteV/Config/Secrets.xcconfig`
2. Fill in your Deepgram key (required for STT)
3. Optionally set Meta DAT credentials for glasses (`MetaAppID=0` enables Developer Mode without credentials)

`Secrets.xcconfig` is gitignored — your keys stay local.

### LLM Provider (in-app)

Tap the gear icon in-app → select provider (Gemini / OpenAI / Anthropic / Custom) → enter API key. Keys are stored in UserDefaults.

### Courses

Chat with NoteV → tell it your schedule naturally → confirm the action card.

## Design System

| Token | Value |
|-------|-------|
| Background | `#0D1117` |
| Surface | `#161B22` |
| Accent | `#00E5FF` |
| Text Primary | `#FFFFFF` |
| Text Secondary | `#8B949E` |
| Bookmark | `#FF6B35` |
| Font | SF Pro (system) |

All design tokens are centralized in `NoteVConfig.Design`.

## Known Limitations

- Glasses features require a physical iPhone (no simulator support for DAT SDK)
- Apple Speech fallback STT has ~1 minute recognition limit (auto-restarts)
- No permission pre-ask flow — iOS will prompt on first use of camera/mic/speech
- Image loading in transcript timeline is synchronous (may cause scroll jank with many images)

## License

MIT License. See [LICENSE](LICENSE) for details.
