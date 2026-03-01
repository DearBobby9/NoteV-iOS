import Foundation

// MARK: - TodoParseError

enum TodoParseError: LocalizedError {
    case invalidEncoding
    case jsonDecodeFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Failed to convert LLM response to UTF-8 string"
        case .jsonDecodeFailed(let detail):
            return "JSON decode failed: \(detail)"
        case .emptyResponse:
            return "LLM returned empty response"
        }
    }
}

// MARK: - LLM Response Models (intermediate)

/// Intermediate Codable struct matching the LLM JSON output schema.
private struct LLMTodoResponse: Codable {
    let todos: [LLMTodoItem]
}

private struct LLMTodoItem: Codable {
    let title: String
    let category: String?
    let priority: String?
    let dateQuote: String?
    let isCalendarEvent: Bool?
    let sourceTimestamp: String?   // "MM:SS" format
    let sourceQuote: String?
    let confidence: Int?
}

// MARK: - TodoParser

/// Parses LLM JSON response into [TodoItem].
/// Pattern mirrors PolishedTranscriptParser.
final class TodoParser {

    private let dateResolver = NaturalDateResolver()

    /// Parse JSON string from LLM into TodoItem array.
    func parse(jsonString: String, sessionDate: Date) throws -> [TodoItem] {
        let cleaned = stripCodeFences(jsonString)

        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TodoParseError.emptyResponse
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw TodoParseError.invalidEncoding
        }

        let decoder = JSONDecoder()
        let response: LLMTodoResponse
        do {
            response = try decoder.decode(LLMTodoResponse.self, from: data)
        } catch {
            NSLog("[TodoParser] JSON decode failed. Raw input (first 500 chars): \(String(cleaned.prefix(500)))")
            throw TodoParseError.jsonDecodeFailed(error.localizedDescription)
        }

        let items = response.todos.compactMap { raw -> TodoItem? in
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let category = TodoCategory(rawValue: raw.category ?? "other") ?? .other
            let priority = TodoPriority(rawValue: raw.priority ?? "medium") ?? .medium
            let confidence = max(1, min(5, raw.confidence ?? 3))
            let timestamp = parseTimestamp(raw.sourceTimestamp)

            // Resolve date from verbatim quote
            var resolvedDate: Date? = nil
            if let quote = raw.dateQuote, !quote.isEmpty {
                resolvedDate = dateResolver.resolve(quote, relativeTo: sessionDate)
            }

            return TodoItem(
                title: title,
                category: category,
                priority: priority,
                dateQuote: raw.dateQuote,
                resolvedDueDate: resolvedDate,
                isCalendarEvent: raw.isCalendarEvent ?? false,
                sourceTimestamp: timestamp,
                sourceQuote: raw.sourceQuote ?? "",
                confidence: confidence
            )
        }

        // Filter by minimum confidence and cap count
        let filtered = items
            .filter { $0.confidence >= NoteVConfig.TodoExtraction.minConfidence }
            .prefix(NoteVConfig.TodoExtraction.maxTodosPerSession)

        NSLog("[TodoParser] Parsed \(response.todos.count) raw → \(filtered.count) filtered items")
        return Array(filtered)
    }

    // MARK: - Helpers

    /// Strip markdown code fences that LLMs sometimes add.
    private func stripCodeFences(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` or ``` ... ```
        if text.hasPrefix("```") {
            // Remove opening fence (may include language tag)
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            // Remove closing fence
            if text.hasSuffix("```") {
                text = String(text.dropLast(3))
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse "MM:SS" timestamp string to TimeInterval (seconds).
    private func parseTimestamp(_ timestampString: String?) -> TimeInterval {
        guard let str = timestampString else { return 0 }

        let components = str.split(separator: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]) else {
            return 0
        }

        return TimeInterval(minutes * 60 + seconds)
    }
}

// MARK: - NaturalDateResolver

/// Resolves natural language date phrases to absolute dates using NSDataDetector.
final class NaturalDateResolver {

    private let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    /// Resolve a natural language date phrase relative to a session date.
    /// Returns nil if no date can be extracted.
    func resolve(_ dateQuote: String, relativeTo sessionDate: Date) -> Date? {
        guard let detector = detector else { return nil }

        let range = NSRange(dateQuote.startIndex..., in: dateQuote)
        let matches = detector.matches(in: dateQuote, options: [], range: range)

        if let match = matches.first, let date = match.date {
            // NSDataDetector resolves relative dates against the current date.
            // Offset the result so it's relative to sessionDate instead.
            let now = Date()
            let calendar = Calendar.current
            let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                     to: calendar.startOfDay(for: sessionDate)).day ?? 0
            if dayOffset != 0 {
                return calendar.date(byAdding: .day, value: dayOffset, to: date)
            }
            return date
        }

        // Fallback: keyword-based heuristics
        return resolveWithHeuristics(dateQuote, relativeTo: sessionDate)
    }

    private func resolveWithHeuristics(_ phrase: String, relativeTo anchor: Date) -> Date? {
        let lower = phrase.lowercased()
        let calendar = Calendar.current

        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: anchor)
        }
        if lower.contains("end of week") || lower.contains("this friday") {
            return calendar.nextDate(
                after: anchor,
                matching: DateComponents(weekday: 6),
                matchingPolicy: .nextTime
            )
        }
        if lower.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: anchor)
        }
        if lower.contains("tonight") || lower.contains("end of day") {
            return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: anchor)
        }

        return nil
    }
}
