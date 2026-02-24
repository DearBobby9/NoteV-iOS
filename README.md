# NoteV

**AI classroom assistant for Meta Ray-Ban smart glasses.**

Every AI note-taker can hear. Ours can see.

NoteV captures audio + visual content during lectures via Meta Ray-Ban Gen-2 smart glasses (or iPhone camera fallback), then generates structured multimodal notes using LLM.

## Architecture

```
Capture Layer     → CaptureProvider protocol (Glasses or Phone)
                     ↓ timestamped frames + audio
Processing Layer  → AudioPipeline (Apple Speech on-device STT)
                  → FramePipeline (periodic sampling + change detection)
                  → BookmarkDetector (manual button)
                  → SessionRecorder (orchestrator)
                     ↓
Generation Layer  → PromptBuilder → LLM API → NoteParser
                     ↓ StructuredNotes
Presentation      → SwiftUI views (Start → Live → Notes)
```

## Tech Stack

- **Platform**: iOS 17+ / Swift / SwiftUI
- **Hardware**: Meta Ray-Ban Gen-2 (DAT SDK) with iPhone camera fallback
- **STT**: Apple Speech (on-device)
- **LLM**: Gemini / OpenAI / Anthropic (configurable in-app)
- **Storage**: FileManager + JSON + JPEG (no CoreData)

## Current Status

### Done

- **End-to-end pipeline** working on real device (iPhone fallback mode)
- **PhoneCaptureProvider**: AVCaptureSession (back camera) + AVAudioEngine (16kHz mono PCM)
- **AudioPipeline**: Apple Speech on-device STT with auto-restart (~1min recognition limit)
- **FramePipeline**: 5s periodic sampling + 64x64 grayscale pixel-difference change detection
- **Manual bookmarks**: haptic feedback, high-res photo capture, orange UI markers in transcript + notes
- **LLMService**: OpenAI / Gemini / Anthropic / custom OpenAI-compatible endpoint support
- **In-app Settings**: provider picker, model selection, API key entry — persisted in UserDefaults
- **Note generation**: multimodal prompt with up to 20 frames + full transcript → structured notes with inline images
- **Session persistence**: JSON + JPEG, session list, load/save/delete
- **Dark design system**: consistent color tokens, bookmark orange (#FF6B35) treatment
- **Transcript deduplication**: interim→final overlap removal + restart-boundary dedup

### In Progress / Next

- **GlassesCaptureProvider**: DAT SDK integration (currently stubbed)
- **DeepgramService**: cloud STT for longer sessions (scaffolded, not implemented)
- **Demo polish**: retry UI for LLM failures, session title backfill from generated notes, PDF export
- **Permission pre-ask flow**: camera/mic/speech authorization UX

## Build & Run

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Generate Xcode project
cd NoteV
xcodegen generate

# Open in Xcode
open NoteV.xcodeproj

# Build from CLI
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project NoteV.xcodeproj -scheme NoteV \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project NoteV.xcodeproj -scheme NoteV \
  test -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Configuration

On first launch, tap the gear icon on the home screen to configure:
1. Select LLM provider (Gemini / OpenAI / Anthropic / Custom)
2. Enter your API key
3. Optionally change the model

Settings persist across app restarts via UserDefaults.

## License

Proprietary. All rights reserved.
