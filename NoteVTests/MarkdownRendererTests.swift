import SwiftUI
import XCTest
@testable import NoteV

final class MarkdownRendererTests: XCTestCase {

    func testBoldTextIsRendered() {
        let result = MarkdownRenderer.attributedString(
            from: "This is **important** content.",
            foregroundColor: .primary
        )

        XCTAssertEqual(String(result.characters), "This is important content.")

        let hasBold = result.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        }
        XCTAssertTrue(hasBold, "Expected bold styling on emphasized text")
    }

    func testBulletListIsParsed() {
        let markdown = """
        - First item
        - Second item
        """

        let result = MarkdownRenderer.attributedString(
            from: markdown,
            foregroundColor: .primary,
            style: .full
        )

        let plainText = String(result.characters)
        XCTAssertTrue(plainText.contains("First item"))
        XCTAssertTrue(plainText.contains("Second item"))

        let hasList = result.runs.contains { run in
            run.presentationIntent?.components.contains(where: { component in
                if case .listItem = component.kind { return true }
                return false
            }) == true
        }
        XCTAssertTrue(hasList, "Expected list item presentation intent")
    }

    func testInlineOnlyPreservesWhitespace() {
        let markdown = "Line one\nLine two"

        let result = MarkdownRenderer.attributedString(
            from: markdown,
            foregroundColor: .primary,
            style: .inlineOnly
        )

        XCTAssertEqual(String(result.characters), markdown)
    }

    func testEmptyStringReturnsEmptyAttributedString() {
        let result = MarkdownRenderer.attributedString(
            from: "",
            foregroundColor: .primary
        )

        XCTAssertTrue(result.characters.isEmpty)
    }

    func testInvalidMarkdownFallsBackToPlainText() {
        let markdown = "Plain lecture notes without special syntax."

        let result = MarkdownRenderer.attributedString(
            from: markdown,
            foregroundColor: .primary
        )

        XCTAssertEqual(String(result.characters), markdown)
    }
}
