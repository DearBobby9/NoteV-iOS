import UIKit

// MARK: - PDFGenerator

/// Generates a PDF document from StructuredNotes with inline images.
final class PDFGenerator {

    // MARK: - Layout Constants

    private let pageWidth: CGFloat = 612   // A4 width in points
    private let pageHeight: CGFloat = 792  // A4 height in points
    private let margin: CGFloat = 40
    private var contentWidth: CGFloat { pageWidth - margin * 2 }

    private let imageStore = ImageStore()

    // MARK: - Generate

    /// Generate a PDF Data blob from structured notes.
    func generatePDF(notes: StructuredNotes, sessionId: UUID?) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            var y: CGFloat = 0

            let beginNewPage: () -> CGFloat = {
                context.beginPage()
                return self.margin
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageHeight - margin {
                    y = beginNewPage()
                }
            }

            // -- Page 1 --
            y = beginNewPage()

            // Title
            let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]
            y = drawTextPaginated(
                notes.title,
                attributes: titleAttrs,
                at: y,
                width: contentWidth,
                margin: margin,
                pageHeight: pageHeight,
                bottomMargin: margin,
                beginNewPage: beginNewPage
            )
            y += 8

            // Date + model
            let metaFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: metaFont,
                .foregroundColor: UIColor.darkGray
            ]
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            let metaText = "Generated \(dateFormatter.string(from: notes.generatedAt)) · \(notes.modelUsed)"
            y = drawTextPaginated(
                metaText,
                attributes: metaAttrs,
                at: y,
                width: contentWidth,
                margin: margin,
                pageHeight: pageHeight,
                bottomMargin: margin,
                beginNewPage: beginNewPage
            )
            y += 16

            // Summary
            let headingFont = UIFont.systemFont(ofSize: 16, weight: .semibold)
            let headingAttrs: [NSAttributedString.Key: Any] = [
                .font: headingFont,
                .foregroundColor: UIColor.black
            ]
            let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: {
                    let ps = NSMutableParagraphStyle()
                    ps.lineSpacing = 4
                    return ps
                }()
            ]

            ensureSpace(40)
            y = drawTextPaginated(
                "Summary",
                attributes: headingAttrs,
                at: y,
                width: contentWidth,
                margin: margin,
                pageHeight: pageHeight,
                bottomMargin: margin,
                beginNewPage: beginNewPage
            )
            y += 4
            y = drawTextPaginated(
                notes.summary,
                attributes: bodyAttrs,
                at: y,
                width: contentWidth,
                margin: margin,
                pageHeight: pageHeight,
                bottomMargin: margin,
                beginNewPage: beginNewPage
            )
            y += 16

            // Key Takeaways
            if !notes.keyTakeaways.isEmpty {
                ensureSpace(40)
                y = drawTextPaginated(
                    "Key Takeaways",
                    attributes: headingAttrs,
                    at: y,
                    width: contentWidth,
                    margin: margin,
                    pageHeight: pageHeight,
                    bottomMargin: margin,
                    beginNewPage: beginNewPage
                )
                y += 4
                for (index, takeaway) in notes.keyTakeaways.enumerated() {
                    y = drawTextPaginated(
                        "\(index + 1). \(takeaway)",
                        attributes: bodyAttrs,
                        at: y,
                        width: contentWidth,
                        margin: margin,
                        pageHeight: pageHeight,
                        bottomMargin: margin,
                        beginNewPage: beginNewPage
                    )
                    y += 2
                }
                y += 12
            }

            // Sections
            for section in notes.sections.sorted(by: { $0.order < $1.order }) {
                ensureSpace(50)

                var sectionTitle = section.title
                if let range = section.formattedTimeRange {
                    sectionTitle += "  [\(range)]"
                }

                y = drawTextPaginated(
                    sectionTitle,
                    attributes: headingAttrs,
                    at: y,
                    width: contentWidth,
                    margin: margin,
                    pageHeight: pageHeight,
                    bottomMargin: margin,
                    beginNewPage: beginNewPage
                )
                y += 4
                y = drawTextPaginated(
                    section.content,
                    attributes: bodyAttrs,
                    at: y,
                    width: contentWidth,
                    margin: margin,
                    pageHeight: pageHeight,
                    bottomMargin: margin,
                    beginNewPage: beginNewPage
                )
                y += 8

                // Inline images
                if let sid = sessionId {
                    for image in section.images {
                        guard let imageData = imageStore.loadImage(filename: image.filename, sessionId: sid),
                              let uiImage = UIImage(data: imageData) else { continue }

                        let maxImageWidth = contentWidth
                        let maxImageHeight: CGFloat = 300
                        let aspectRatio = uiImage.size.width / uiImage.size.height
                        var drawWidth = maxImageWidth
                        var drawHeight = drawWidth / aspectRatio
                        if drawHeight > maxImageHeight {
                            drawHeight = maxImageHeight
                            drawWidth = drawHeight * aspectRatio
                        }

                        ensureSpace(drawHeight + 24)
                        let imageRect = CGRect(x: margin, y: y, width: drawWidth, height: drawHeight)
                        uiImage.draw(in: imageRect)
                        y += drawHeight + 4

                        // Caption
                        if !image.caption.isEmpty {
                            let captionAttrs: [NSAttributedString.Key: Any] = [
                                .font: UIFont.italicSystemFont(ofSize: 10),
                                .foregroundColor: UIColor.gray
                            ]
                            y = drawTextPaginated(
                                image.caption,
                                attributes: captionAttrs,
                                at: y,
                                width: contentWidth,
                                margin: margin,
                                pageHeight: pageHeight,
                                bottomMargin: margin,
                                beginNewPage: beginNewPage
                            )
                        }
                        y += 12
                    }
                }
                y += 8
            }

            // Footer
            ensureSpace(30)
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]
            y = drawTextPaginated(
                "Generated by NoteV",
                attributes: footerAttrs,
                at: y,
                width: contentWidth,
                margin: margin,
                pageHeight: pageHeight,
                bottomMargin: margin,
                beginNewPage: beginNewPage
            )
        }

        NSLog("[PDFGenerator] Generated PDF: \(data.count) bytes")
        return data
    }

    // MARK: - Drawing Helpers

    /// Draw text with automatic page breaks, returning the new y position.
    private func drawTextPaginated(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        at startY: CGFloat,
        width: CGFloat,
        margin: CGFloat,
        pageHeight: CGFloat,
        bottomMargin: CGFloat,
        beginNewPage: () -> CGFloat
    ) -> CGFloat {
        guard !text.isEmpty else { return startY }

        var y = startY
        var remaining = text

        while !remaining.isEmpty {
            let availableHeight = pageHeight - bottomMargin - y
            if availableHeight <= 1 {
                y = beginNewPage()
                continue
            }

            let fittingCount = bestFittingPrefixCount(
                in: remaining,
                attributes: attributes,
                width: width,
                maxHeight: availableHeight
            )

            guard fittingCount > 0 else {
                y = beginNewPage()
                continue
            }

            let splitCount = adjustedSplitCount(in: remaining, candidate: fittingCount)
            let chunk = String(remaining.prefix(splitCount))
            let chunkHeight = textHeight(chunk, attributes: attributes, width: width)
            let drawRect = CGRect(x: margin, y: y, width: width, height: chunkHeight)
            NSAttributedString(string: chunk, attributes: attributes).draw(in: drawRect)
            y += chunkHeight

            if splitCount >= remaining.count {
                break
            }

            remaining = String(remaining.dropFirst(splitCount))
            y = beginNewPage()
        }

        return y
    }

    private func textHeight(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let boundingRect = attrString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(boundingRect.height)
    }

    private func bestFittingPrefixCount(
        in text: String,
        attributes: [NSAttributedString.Key: Any],
        width: CGFloat,
        maxHeight: CGFloat
    ) -> Int {
        if textHeight(text, attributes: attributes, width: width) <= maxHeight {
            return text.count
        }

        var low = 1
        var high = text.count
        var best = 0

        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(text.prefix(mid))
            let height = textHeight(candidate, attributes: attributes, width: width)
            if height <= maxHeight {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best
    }

    private func adjustedSplitCount(in text: String, candidate: Int) -> Int {
        guard candidate < text.count else { return candidate }

        let splitIndex = text.index(text.startIndex, offsetBy: candidate)
        var cursor = splitIndex

        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            if text[previous].isWhitespace {
                let adjusted = text.distance(from: text.startIndex, to: cursor)
                if adjusted >= max(1, candidate / 2) {
                    return adjusted
                }
                break
            }
            cursor = previous
        }

        return candidate
    }
}
