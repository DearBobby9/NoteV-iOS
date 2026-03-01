import SwiftUI

// MARK: - TranscriptTimelineView

/// Layer 1: Chronological polished transcript timeline with inline images.
/// Displays AI-polished transcript segments in a vertical timeline layout
/// with timestamps, bookmark highlights, and captured frame images.
struct TranscriptTimelineView: View {
    let transcript: PolishedTranscript
    var sessionId: UUID?

    private let imageStore = ImageStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(transcript.segments) { segment in
                    segmentRow(segment)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Segment Row

    private func segmentRow(_ segment: PolishedSegment) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left gutter: timestamp
            timestampLabel(segment.startTime)
                .frame(width: NoteVConfig.Design.timelineGutterWidth, alignment: .trailing)

            // Timeline rail + dot
            VStack(spacing: 0) {
                // Top rail segment
                Rectangle()
                    .fill(NoteVConfig.Design.timelineRailColor)
                    .frame(width: NoteVConfig.Design.timelineRailWidth, height: 8)

                // Dot
                Circle()
                    .fill(segment.isBookmarked
                          ? NoteVConfig.Design.bookmarkHighlight
                          : NoteVConfig.Design.accent.opacity(0.6))
                    .frame(
                        width: segment.isBookmarked
                            ? NoteVConfig.Design.timelineSectionDotSize
                            : NoteVConfig.Design.timelineDotSize,
                        height: segment.isBookmarked
                            ? NoteVConfig.Design.timelineSectionDotSize
                            : NoteVConfig.Design.timelineDotSize
                    )

                // Bottom rail segment (extends to full height)
                Rectangle()
                    .fill(NoteVConfig.Design.timelineRailColor)
                    .frame(width: NoteVConfig.Design.timelineRailWidth)
            }
            .frame(width: 16)

            // Content: text + images
            VStack(alignment: .leading, spacing: 8) {
                Text(segment.text)
                    .font(.body)
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                    .lineSpacing(4)

                // Inline images
                ForEach(segment.images) { image in
                    imageCard(image)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, NoteVConfig.Design.padding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                segment.isBookmarked
                    ? NoteVConfig.Design.bookmarkHighlight.opacity(0.08)
                    : Color.clear
            )
        }
    }

    // MARK: - Timestamp Label

    private func timestampLabel(_ seconds: TimeInterval) -> some View {
        Text(formatTimestamp(seconds))
            .font(.caption2)
            .fontWeight(.medium)
            .monospacedDigit()
            .foregroundColor(NoteVConfig.Design.textSecondary)
            .padding(.trailing, 6)
    }

    // MARK: - Image Card

    private func imageCard(_ image: TimelineImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sessionId = sessionId,
               let data = imageStore.loadImage(filename: image.filename, sessionId: sessionId),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(NoteVConfig.Design.surface, lineWidth: 1)
                    )
            }

            // Caption: timestamp + trigger type
            HStack(spacing: 4) {
                Image(systemName: triggerIcon(image.trigger))
                    .font(.caption2)
                Text(formatTimestamp(image.timestamp))
                    .font(.caption2)
                    .monospacedDigit()
                Text("·")
                    .font(.caption2)
                Text(triggerLabel(image.trigger))
                    .font(.caption2)
            }
            .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.7))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func triggerIcon(_ trigger: FrameTrigger) -> String {
        switch trigger {
        case .periodic: return "clock"
        case .changeDetected: return "rectangle.on.rectangle"
        case .bookmark: return "bookmark.fill"
        }
    }

    private func triggerLabel(_ trigger: FrameTrigger) -> String {
        switch trigger {
        case .periodic: return "periodic"
        case .changeDetected: return "content change"
        case .bookmark: return "bookmarked"
        }
    }
}
