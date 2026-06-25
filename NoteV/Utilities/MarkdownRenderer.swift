import Foundation
import SwiftUI

// MARK: - MarkdownRenderer

/// Converts markdown strings from the LLM into styled AttributedString values.
enum MarkdownRenderer {

    enum Style {
        /// Block-level markdown: lists, headings, paragraphs.
        case full
        /// Inline-only markdown for short chat messages.
        case inlineOnly
    }

    static func attributedString(
        from text: String,
        foregroundColor: Color,
        style: Style = .full
    ) -> AttributedString {
        guard !text.isEmpty else {
            return AttributedString("")
        }

        do {
            let options: AttributedString.MarkdownParsingOptions = switch style {
            case .full:
                .init()
            case .inlineOnly:
                .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            }

            var result = try AttributedString(markdown: text, options: options)
            result.foregroundColor = foregroundColor
            return result
        } catch {
            var fallback = AttributedString(text)
            fallback.foregroundColor = foregroundColor
            return fallback
        }
    }
}
