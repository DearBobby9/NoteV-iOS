<h1 align="center">
  <br>
  <img src="simulator_screenshot.png" alt="NoteV" width="120">
  <br>
  NoteV
  <br>
</h1>

<h3 align="center"><strong>Every AI note-taker can hear. Ours can see.</strong></h3>

<p align="center">
  AI classroom assistant for Meta Ray-Ban smart glasses.<br>
  Captures audio + visual content during lectures → generates structured multimodal notes.
</p>

<p align="center">
  <a href="#get-started-in-5-minutes">Quick Start</a> •
  <a href="#features">Features</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#tech-stack">Tech Stack</a>
</p>

---

> **No glasses? No problem.** NoteV works with your iPhone camera as a fallback — same full pipeline, no extra hardware needed. Point your phone at the whiteboard and go.

<!--
TODO: Add demo video here once recorded
[![Demo Video](https://img.shields.io/badge/Watch-Demo_Video-red?style=for-the-badge&logo=youtube)](YOUR_YOUTUBE_LINK)
-->

## Get Started in 5 Minutes

**What you need:**
- Xcode 15+ on macOS
- A free [Deepgram API key](https://console.deepgram.com/) (for speech-to-text)
- Any one LLM API key: [Gemini](https://aistudio.google.com/apikey) (free tier available) / [OpenAI](https://platform.openai.com/api-keys) / [Anthropic](https://console.anthropic.com/)
- iPhone or iOS Simulator (Meta Ray-Ban glasses are optional)

```bash
# Clone
git clone https://github.com/DearBobby9/NoteV-iOS.git
cd NoteV-iOS

# Set up API keys
cp NoteV/Config/Secrets.xcconfig.example NoteV/Config/Secrets.xcconfig
# Edit Secrets.xcconfig — paste your Deepgram key

# Open & run
open NoteV.xcodeproj
# In Xcode: select your device/simulator → Cmd+R
# On first launch: tap ⚙️ → select LLM provider → enter API key
```

`Secrets.xcconfig` is gitignored — your keys stay local.

## Features

### Three-Layer Output Pipeline

| Layer | What it does |
|-------|-------------|
| **Polished Timeline** | AI-cleaned transcript with inline images, bookmark highlights, and sticky section headers |
| **AI Notes** | Structured notes organized by slide transitions with timestamps and table of contents |
| **Action Items** | Extracted TODOs with categories, priorities, due dates → batch export to iOS Reminders & Calendar |

### Smart Recording

- **Dual capture** — Meta Ray-Ban glasses via DAT SDK, or iPhone back camera (automatic fallback)
- **Real-time STT** — Deepgram WebSocket streaming with KeepAlive and graceful shutdown
- **Smart bookmarks** — Auto-detects key moments ("this will be on the exam", "important") via 4-tier keyword taxonomy with confidence scoring
- **Frame intelligence** — 5s periodic sampling + SSIM change detection + pHash slide deduplication
- **Slide analysis** — LLM vision reads slide content (titles, bullets, formulas, diagrams) — not OCR

### AI Chat System

- **Unified chat** — Ask questions about your notes, set up courses, configure settings, create reminders — all through natural language
- **Voice input** — Deepgram-powered dictation
- **Action cards** — Confirmable UI buttons for adding courses, changing settings, creating reminders
- **Session context** — Chat has access to your transcript, notes, slides, and todos

### Course Management

- **Conversational setup** — Tell the AI your schedule naturally ("I have CS229 MWF 10am") — no forms
- **Auto-detection** — Detects which course you're in when recording starts
- **Weekly calendar** — iOS Calendar-style grid view with course blocks and live time indicator

### Export

- **Export Preview** — Review and edit action items before batch export (toggle Reminder vs Calendar Event, edit titles/dates/priorities)
- **PDF generation** — Formatted PDF with inline images and section timestamps
- **iOS Reminders** — Batch export to dedicated "NoteV Tasks" list with deep links back to session timestamps

## Architecture

```mermaid
graph TD
    subgraph Capture
        A[CaptureProvider Protocol] --> B[Meta Ray-Ban<br/>DAT SDK]
        A --> C[iPhone Camera<br/>AVCaptureSession]
    end

    subgraph Processing
        D[AudioPipeline<br/>Deepgram / Apple Speech]
        E[FramePipeline<br/>SSIM + pHash dedup]
        F[SmartBookmarkDetector<br/>4-tier keyword scoring]
        G[SessionRecorder<br/>orchestrator]
    end

    subgraph Generation
        H[TranscriptPolisher<br/>chunked LLM cleanup]
        I[SlideAnalyzer<br/>LLM vision extraction]
        J[NoteGenerator<br/>multimodal LLM]
        K[TodoExtractor<br/>action item extraction]
    end

    subgraph Presentation
        L["Layer 1: Polished Timeline"]
        M["Layer 2: AI Notes"]
        N["Layer 3: Action Items"]
        O[AI Chat + Course Management]
    end

    A -- "frames + audio" --> D & E
    D & E & F --> G
    G --> H & I
    H & I --> J
    J --> K
    H --> L
    J --> M
    K --> N
    G --> O
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Platform | iOS 17+ / Swift 6 / SwiftUI |
| Smart Glasses | Meta Ray-Ban Gen-2 (DAT SDK v0.4.0) |
| Speech-to-Text | Deepgram nova-3 via native WebSocket (primary) / Apple Speech (fallback) |
| LLM | OpenAI GPT-4o / Anthropic Claude / Google Gemini (configurable) |
| Native Frameworks | EventKit, PDFKit, Speech, AVFoundation |
| Storage | FileManager + JSON + JPEG (no CoreData) |

## Project Structure

```
NoteV/
├── App/              # Entry point, AppState (session lifecycle)
├── Capture/          # CaptureProvider protocol, Glasses + Phone providers
├── Processing/       # AudioPipeline, FramePipeline, SessionRecorder, SmartBookmarkDetector
├── NoteGeneration/   # NoteGenerator, TranscriptPolisher, TodoExtractor, SlideAnalyzer, PDFGenerator
├── Services/         # DeepgramService, LLMService, ReminderSyncService
├── Models/           # SessionData, TranscriptSegment, Bookmark, TodoItem, Course
├── Storage/          # SessionStore, CourseStore, ChatStore, ImageStore
├── Views/            # SwiftUI screens + reusable components
└── Config/           # NoteVConfig (all tunable params), xcconfig files
```

## Known Limitations

- Glasses features require a physical iPhone (DAT SDK doesn't run in simulator)
- Apple Speech fallback has ~1 min recognition limit (auto-restarts)
- No permission pre-ask flow — iOS prompts on first camera/mic/speech use

## License

MIT License. See [LICENSE](LICENSE) for details.
