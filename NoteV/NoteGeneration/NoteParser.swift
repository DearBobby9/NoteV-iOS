import Foundation

// MARK: - NoteParser

/// Parses LLM markdown response into StructuredNotes.
final class NoteParser {

    // MARK: - Init

    init() {
        NSLog("[NoteParser] Initialized")
    }

    // MARK: - Parsing

    /// Parse a markdown string from the LLM into StructuredNotes.
    /// - Parameter imageFilenameMap: Mapping from image_N index → actual frame filename on disk.
    ///   Must match the indices used in the prompt (built from includedFrames).
    func parse(markdown: String, imageFilenameMap: [Int: String] = [:], modelUsed: String = NoteVConfig.NoteGeneration.llmModel) -> StructuredNotes {
        NSLog("[NoteParser] parse() called — input length: \(markdown.count) chars")

        let lines = markdown.components(separatedBy: "\n")

        var title = "Lecture Notes"
        var summary = ""
        var keyTakeaways: [String] = []
        var sections: [NoteSection] = []

        var currentSectionTitle: String?
        var currentSectionContent: [String] = []
        var currentSectionImages: [NoteImage] = []
        var currentSectionStartTime: TimeInterval?
        var currentSectionEndTime: TimeInterval?
        var currentSectionIsBookmark: Bool = false
        var sectionOrder = 0
        var parsingState: ParsingState = .seekingTitle

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // H1: Title
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                parsingState = .seekingSection
                continue
            }

            // H2: Section header
            if trimmed.hasPrefix("## ") {
                // Flush previous section
                flushSection(
                    title: &currentSectionTitle,
                    content: &currentSectionContent,
                    images: &currentSectionImages,
                    sections: &sections,
                    order: &sectionOrder,
                    startTime: &currentSectionStartTime,
                    endTime: &currentSectionEndTime,
                    isBookmark: &currentSectionIsBookmark
                )

                let rawSectionName = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)

                if rawSectionName.lowercased() == "summary" {
                    parsingState = .parsingSummary
                } else if rawSectionName.lowercased() == "key takeaways" || rawSectionName.lowercased() == "key points" {
                    parsingState = .parsingTakeaways
                } else {
                    let (cleanTitle, startTime, endTime) = parseTimestampRange(from: rawSectionName)
                    let isBookmark = cleanTitle.hasPrefix("[BOOKMARK]") || cleanTitle.localizedCaseInsensitiveContains("bookmark")
                    let displayTitle = cleanTitle
                        .replacingOccurrences(of: "[BOOKMARK] ", with: "")
                        .replacingOccurrences(of: "[BOOKMARK]", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    currentSectionTitle = displayTitle
                    currentSectionStartTime = startTime
                    currentSectionEndTime = endTime
                    currentSectionIsBookmark = isBookmark
                    parsingState = .parsingSection
                }
                continue
            }

            // Content based on state
            switch parsingState {
            case .seekingTitle, .seekingSection:
                continue

            case .parsingSummary:
                if !trimmed.isEmpty {
                    if summary.isEmpty {
                        summary = trimmed
                    } else {
                        summary += " " + trimmed
                    }
                }

            case .parsingTakeaways:
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    let takeaway = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if !takeaway.isEmpty {
                        keyTakeaways.append(takeaway)
                    }
                } else if let first = trimmed.first, first.isNumber, trimmed.contains(".") {
                    // [P3 fix] Numbered list — support any digit prefix (1. 2. ... 10. etc.)
                    if let dotIndex = trimmed.firstIndex(of: ".") {
                        let takeaway = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                        if !takeaway.isEmpty {
                            keyTakeaways.append(takeaway)
                        }
                    }
                }

            case .parsingSection:
                // Check for image references: ![image_N](caption)
                if trimmed.hasPrefix("![") {
                    if let imageRef = parseImageReference(trimmed, imageFilenameMap: imageFilenameMap) {
                        currentSectionImages.append(imageRef)
                    } else {
                        // Intentionally skip broken/unmapped image refs instead of leaking raw markdown.
                        continue
                    }
                } else {
                    currentSectionContent.append(line)
                }
            }
        }

        // Flush final section
        flushSection(
            title: &currentSectionTitle,
            content: &currentSectionContent,
            images: &currentSectionImages,
            sections: &sections,
            order: &sectionOrder,
            startTime: &currentSectionStartTime,
            endTime: &currentSectionEndTime,
            isBookmark: &currentSectionIsBookmark
        )

        // Fallback: if no sections parsed, put entire content as one section
        if sections.isEmpty && !markdown.isEmpty {
            sections.append(NoteSection(
                title: "Notes",
                content: markdown,
                order: 0
            ))
        }

        let notes = StructuredNotes(
            title: title,
            summary: summary,
            sections: sections,
            keyTakeaways: keyTakeaways,
            modelUsed: modelUsed
        )

        NSLog("[NoteParser] Parsed — title: \"\(title)\", \(sections.count) sections, \(keyTakeaways.count) takeaways")
        return notes
    }

    // MARK: - Helpers

    private enum ParsingState {
        case seekingTitle
        case seekingSection
        case parsingSummary
        case parsingTakeaways
        case parsingSection
    }

    private func flushSection(
        title: inout String?,
        content: inout [String],
        images: inout [NoteImage],
        sections: inout [NoteSection],
        order: inout Int,
        startTime: inout TimeInterval?,
        endTime: inout TimeInterval?,
        isBookmark: inout Bool
    ) {
        guard let sectionTitle = title else { return }

        let sectionContent = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sectionContent.isEmpty || !images.isEmpty {
            sections.append(NoteSection(
                title: sectionTitle,
                content: sectionContent,
                images: images,
                order: order,
                startTime: startTime,
                endTime: endTime,
                isBookmarkSection: isBookmark
            ))
            order += 1
        }

        title = nil
        content = []
        images = []
        startTime = nil
        endTime = nil
        isBookmark = false
    }

    /// Parse "[MM:SS-MM:SS]" from end of section title.
    /// Returns (cleanTitle, startTime, endTime) or (originalTitle, nil, nil) if no timestamp found.
    private func parseTimestampRange(from rawTitle: String) -> (String, TimeInterval?, TimeInterval?) {
        let pattern = #"\[(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rawTitle, range: NSRange(rawTitle.startIndex..., in: rawTitle)) else {
            return (rawTitle, nil, nil)
        }

        let startRange = Range(match.range(at: 1), in: rawTitle)!
        let endRange = Range(match.range(at: 2), in: rawTitle)!
        let matchFullRange = Range(match.range, in: rawTitle)!

        let cleanTitle = String(rawTitle[..<matchFullRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let startTime = parseMMSS(String(rawTitle[startRange]))
        let endTime = parseMMSS(String(rawTitle[endRange]))

        return (cleanTitle, startTime, endTime)
    }

    private func parseMMSS(_ str: String) -> TimeInterval? {
        let parts = str.split(separator: ":")
        guard parts.count == 2, let mins = Int(parts[0]), let secs = Int(parts[1]) else { return nil }
        return TimeInterval(mins * 60 + secs)
    }

    /// Parse ![image_N](caption) into NoteImage using the authoritative mapping.
    /// Returns nil if the image index is not in the mapping (LLM hallucinated an index).
    private func parseImageReference(_ text: String, imageFilenameMap: [Int: String]) -> NoteImage? {
        // Match pattern: ![image_N](caption text)
        guard text.hasPrefix("![") else { return nil }

        guard let closeBracket = text.firstIndex(of: "]"),
              let openParen = text.index(closeBracket, offsetBy: 1, limitedBy: text.endIndex),
              text[openParen] == "(",
              let closeParen = text.lastIndex(of: ")") else { return nil }

        let imageName = String(text[text.index(text.startIndex, offsetBy: 2)..<closeBracket])
        let caption = String(text[text.index(after: openParen)..<closeParen])

        // Look up actual filename from the mapping table (built from includedFrames).
        // No guessing — if the index isn't in the map, skip this reference.
        guard let numberStr = imageName.components(separatedBy: "_").last,
              let number = Int(numberStr),
              let filename = imageFilenameMap[number] else {
            NSLog("[NoteParser] WARNING: image reference \"\(imageName)\" not found in mapping — skipping")
            return nil
        }

        return NoteImage(
            filename: filename,
            caption: caption,
            timestamp: 0
        )
    }
}
