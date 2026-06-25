import SwiftUI

// MARK: - MarkdownText

/// Renders markdown content with NoteV styling.
struct MarkdownText: View {
    let text: String
    var foregroundColor: Color = NoteVConfig.Design.textPrimary
    var font: Font = .body
    var style: MarkdownRenderer.Style = .full
    var lineSpacing: CGFloat = 0

    var body: some View {
        Text(MarkdownRenderer.attributedString(
            from: text,
            foregroundColor: foregroundColor,
            style: style
        ))
        .font(font)
        .lineSpacing(lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
