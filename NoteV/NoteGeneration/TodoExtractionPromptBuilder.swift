import Foundation

// MARK: - TodoExtractionPromptBuilder

/// Builds system and user prompts for LLM-based action item extraction.
/// Pattern mirrors TranscriptPolishingPromptBuilder.
enum TodoExtractionPromptBuilder {

    // MARK: - System Prompt

    static var systemPrompt: String {
        """
        You are an expert academic assistant that extracts action items from university lecture transcripts.

        Your task: identify ONLY items that require the student to take action outside of class.

        EXTRACT:
        - Homework assignments with deadlines ("submit lab report by Friday")
        - Reading assignments ("read chapter 5 before next class")
        - Exam/quiz preparation ("midterm is next Wednesday")
        - Project milestones ("proposal due in two weeks")
        - Administrative tasks ("register for lab section")
        - Attendance requirements ("office hours Thursday 2-4pm")

        DO NOT EXTRACT:
        - Facts or concepts being taught (not action items)
        - Things the professor will do ("I'll post the slides")
        - Past-tense items already completed ("last week you submitted")
        - Rhetorical questions ("can you think about what that means?")
        - Hypothetical examples used for teaching

        RULES:
        1. Write each title as an imperative phrase: "Submit X", "Read Y", "Review Z"
        2. For dateQuote, copy the EXACT phrase from the transcript — do NOT resolve to a calendar date
        3. Set isCalendarEvent = true ONLY when a specific date AND time are mentioned (e.g., "exam March 15 at 2pm")
        4. Confidence scale: 5 = explicit deadline with clear obligation, 4 = clear task without exact date, 3 = recommended action, 2 = soft suggestion, 1 = vague mention
        5. Priority: high = explicit deadline within 7 days or exam-related, medium = clear task further out, low = optional or soft suggestion

        Return ONLY valid JSON. No markdown code fences, no explanation text.

        Output format:
        {
          "todos": [
            {
              "title": "Submit Lab Report 3",
              "category": "homework",
              "priority": "high",
              "dateQuote": "due Friday before midnight",
              "isCalendarEvent": false,
              "sourceTimestamp": "14:32",
              "sourceQuote": "Lab report 3 is due Friday before midnight, submit on Canvas",
              "confidence": 5
            }
          ]
        }

        Valid categories: homework, reading, exam_prep, project, quiz, lab, attendance, other
        Valid priorities: high, medium, low

        If no action items are found, return: {"todos": []}
        """
    }

    // MARK: - Build Prompt

    /// Build the user prompt from a session's polished transcript.
    /// Falls back to raw transcript if polished is unavailable.
    static func buildPrompt(session: SessionData) -> String {
        let sessionDate = session.metadata.startDate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd (EEEE)"
        let dateString = dateFormatter.string(from: sessionDate)

        let transcriptText: String
        if let polished = session.polishedTranscript, !polished.segments.isEmpty {
            transcriptText = polished.segments
                .sorted { $0.startTime < $1.startTime }
                .map { segment in
                    let minutes = Int(segment.startTime) / 60
                    let seconds = Int(segment.startTime) % 60
                    return "[\(String(format: "%02d:%02d", minutes, seconds))] \(segment.text)"
                }
                .joined(separator: "\n")
        } else {
            transcriptText = session.transcriptSegments
                .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .sorted { $0.startTime < $1.startTime }
                .map { segment in
                    let minutes = Int(segment.startTime) / 60
                    let seconds = Int(segment.startTime) % 60
                    return "[\(String(format: "%02d:%02d", minutes, seconds))] \(segment.text)"
                }
                .joined(separator: "\n")
        }

        return """
        Session date: \(dateString)
        Session title: \(session.metadata.title)

        TRANSCRIPT:
        \(transcriptText)

        Extract all student action items from this lecture transcript. Return JSON only.
        """
    }
}
