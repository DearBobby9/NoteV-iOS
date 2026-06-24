import Foundation

// MARK: - PostProcessingStage

enum PostProcessingStage: String, CaseIterable, Sendable {
    case finalizing
    case extractingFrames
    case polishing
    case analyzingSlides
    case generatingNotes
    case extractingTodos

    var displayName: String {
        switch self {
        case .finalizing: return "Finalizing session…"
        case .extractingFrames: return "Extracting frames from video…"
        case .polishing: return "Polishing transcript…"
        case .analyzingSlides: return "Analyzing slides…"
        case .generatingNotes: return "Generating notes…"
        case .extractingTodos: return "Extracting action items…"
        }
    }

    var sessionStatus: SessionStatus {
        switch self {
        case .finalizing: return .finalizing
        case .extractingFrames: return .extractingFrames
        case .polishing: return .polishing
        case .analyzingSlides: return .analyzingSlides
        case .generatingNotes: return .generatingNotes
        case .extractingTodos: return .extractingTodos
        }
    }
}

// MARK: - PostProcessingResult

struct PostProcessingResult: Sendable {
    let session: SessionData
    let notes: StructuredNotes?
    let todos: [TodoItem]
    let warnings: [String]
    let failedStage: PostProcessingStage?
}

// MARK: - PostProcessingOrchestrator

/// Runs the staged post-recording pipeline: finalize → extract frames → polish → slides → notes → todos.
@MainActor
final class PostProcessingOrchestrator {

    static let shared = PostProcessingOrchestrator()

    private(set) var isProcessing = false

    private let sessionStore = SessionStore()

    // MARK: - Process

    func process(
        session: SessionData,
        appState: AppState,
        fromStage: PostProcessingStage = .finalizing
    ) async -> PostProcessingResult {
        guard !isProcessing else {
            NSLog("[PostProcessingOrchestrator] Already processing — ignoring duplicate request")
            return PostProcessingResult(
                session: session,
                notes: session.notes,
                todos: session.todos ?? [],
                warnings: ["Processing already in progress"],
                failedStage: nil
            )
        }

        isProcessing = true
        defer { isProcessing = false }

        var updatedSession = session
        var warnings: [String] = []
        var notes: StructuredNotes?
        var todos: [TodoItem] = session.todos ?? []
        var failedStage: PostProcessingStage?

        let stages = PostProcessingStage.allCases
        guard let startIndex = stages.firstIndex(of: fromStage) else {
            isProcessing = false
            return PostProcessingResult(session: session, notes: nil, todos: [], warnings: [], failedStage: .finalizing)
        }

        for stage in stages[startIndex...] {
            await setStage(stage, appState: appState)

            switch stage {
            case .finalizing:
                if updatedSession.transcriptSegments.isEmpty && updatedSession.frames.isEmpty {
                    warnings.append("Session has no transcript or frames")
                } else if updatedSession.transcriptSegments.isEmpty {
                    warnings.append("Live transcription unavailable — notes were generated from video frames only")
                }

            case .extractingFrames:
                if NoteVConfig.FrameExtraction.enabled,
                   let _ = updatedSession.metadata.videoFilename {
                    let videoURL = sessionStore.videoURL(for: updatedSession.id)
                    if FileManager.default.fileExists(atPath: videoURL.path) {
                        do {
                            let extractor = SessionFrameExtractor()
                            updatedSession = try await extractor.extract(session: updatedSession, videoURL: videoURL)
                            appState.currentSession = updatedSession
                            try? sessionStore.save(session: updatedSession)
                            NSLog("[PostProcessingOrchestrator] Frame extraction complete — \(updatedSession.frames.count) frames")
                        } catch {
                            warnings.append("Frame extraction failed — using live preview frames")
                            NSLog("[PostProcessingOrchestrator] Extraction failed (non-fatal): \(error.localizedDescription)")
                        }
                    } else {
                        warnings.append("Session video file missing — using live preview frames")
                    }
                } else if NoteVConfig.FrameExtraction.enabled {
                    warnings.append("No session video — using live preview frames")
                }

            case .polishing:
                if NoteVConfig.TranscriptPolishing.enabled {
                    do {
                        let polisher = TranscriptPolisher()
                        let polished = try await polisher.polish(session: updatedSession)
                        updatedSession.polishedTranscript = polished
                        appState.currentSession = updatedSession
                        try? sessionStore.save(session: updatedSession)
                    } catch {
                        warnings.append("Transcript polishing failed: \(error.localizedDescription)")
                        NSLog("[PostProcessingOrchestrator] Polishing failed (non-fatal): \(error.localizedDescription)")
                    }
                }

            case .analyzingSlides:
                if NoteVConfig.SlideAnalysis.enabled && !updatedSession.frames.isEmpty {
                    do {
                        let analyzer = SlideAnalyzer()
                        let result = try await analyzer.analyze(session: updatedSession)
                        updatedSession.slideAnalysis = result
                        appState.currentSession = updatedSession
                        try? sessionStore.save(session: updatedSession)
                    } catch {
                        warnings.append("Slide analysis failed: \(error.localizedDescription)")
                        NSLog("[PostProcessingOrchestrator] Slide analysis failed (non-fatal): \(error.localizedDescription)")
                    }
                }

            case .generatingNotes:
                do {
                    let generator = NoteGenerator()
                    let generated = try await generator.generateNotes(from: updatedSession)
                    notes = generated
                    appState.generatedNotes = generated
                    updatedSession.metadata.title = generated.title
                    updatedSession.notes = generated
                    appState.currentSession = mergeCourseTag(into: updatedSession, from: appState)
                    updatedSession = appState.currentSession ?? updatedSession
                    try? sessionStore.save(session: updatedSession)
                } catch {
                    failedStage = .generatingNotes
                    appState.sessionStatus = .error(error.localizedDescription)
                    NSLog("[PostProcessingOrchestrator] Note generation failed: \(error.localizedDescription)")
                    return PostProcessingResult(
                        session: updatedSession,
                        notes: nil,
                        todos: todos,
                        warnings: warnings,
                        failedStage: failedStage
                    )
                }

            case .extractingTodos:
                if NoteVConfig.TodoExtraction.enabled {
                    do {
                        let extractor = TodoExtractor()
                        todos = try await extractor.extract(from: updatedSession)
                        appState.extractedTodos = todos
                        updatedSession.todos = todos
                    } catch {
                        warnings.append("TODO extraction failed: \(error.localizedDescription)")
                        updatedSession.todos = []
                        todos = []
                        NSLog("[PostProcessingOrchestrator] TODO extraction failed (non-fatal): \(error.localizedDescription)")
                    }
                }
            }
        }

        updatedSession = mergeCourseTag(into: updatedSession, from: appState)
        appState.currentSession = updatedSession

        do {
            try sessionStore.save(session: updatedSession)
        } catch {
            warnings.append("Could not save session: \(error.localizedDescription)")
        }

        appState.processingWarnings = warnings
        appState.sessionStatus = .complete
        NSLog("[PostProcessingOrchestrator] Pipeline complete — \(warnings.count) warnings")

        return PostProcessingResult(
            session: updatedSession,
            notes: notes,
            todos: todos,
            warnings: warnings,
            failedStage: failedStage
        )
    }

    // MARK: - Private

    private func setStage(_ stage: PostProcessingStage, appState: AppState) async {
        appState.sessionStatus = stage.sessionStatus
        NSLog("[PostProcessingOrchestrator] Stage: \(stage.rawValue)")
    }

    /// Merge course tag from AppState if user selected one during the post-recording sheet.
    private func mergeCourseTag(into session: SessionData, from appState: AppState) -> SessionData {
        var merged = session
        if let current = appState.currentSession {
            if merged.courseId == nil, let courseId = current.courseId {
                merged.courseId = courseId
            }
            if merged.courseName == nil, let courseName = current.courseName {
                merged.courseName = courseName
            }
        }
        return merged
    }
}
