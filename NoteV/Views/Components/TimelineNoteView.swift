import SwiftUI

// MARK: - TimelineNoteView

/// Renders StructuredNotes as a vertical timeline with sticky section headers,
/// a left-side timestamp rail, floating timestamp pill, and TOC button.
struct TimelineNoteView: View {
    let notes: StructuredNotes
    var sessionId: UUID?

    private let imageStore = ImageStore()

    @State private var currentSectionId: UUID?
    @State private var showTOC = false

    private var sortedSections: [NoteSection] {
        notes.sections.sorted { $0.order < $1.order }
    }

    private var currentSection: NoteSection? {
        sortedSections.first { $0.id == currentSectionId }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    timelineContent
                    generationFooter
                }
                .padding(.bottom, 16)
            }
            .coordinateSpace(name: "timeline")
            .onPreferenceChange(SectionPositionKey.self) { positions in
                // Find the section whose header is closest above the top edge
                let visible = positions
                    .filter { $0.value <= 80 }
                    .max(by: { $0.value < $1.value })
                if let top = visible {
                    currentSectionId = top.key
                }
            }
            .overlay(alignment: .top) {
                floatingTimestampPill
            }
            .overlay(alignment: .bottomTrailing) {
                tocButton(proxy: proxy)
            }
        }
    }

    // MARK: - Header Section (no timeline rail)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(notes.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(NoteVConfig.Design.textPrimary)

            // Summary
            if !notes.summary.isEmpty {
                Text(notes.summary)
                    .font(.body)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                    .padding()
                    .background(NoteVConfig.Design.surface)
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            }

            // Key Takeaways
            if !notes.keyTakeaways.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Takeaways")
                        .font(.headline)
                        .foregroundColor(NoteVConfig.Design.accent)

                    ForEach(notes.keyTakeaways, id: \.self) { takeaway in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(NoteVConfig.Design.accent)
                                .padding(.top, 3)

                            Text(takeaway)
                                .font(.body)
                                .foregroundColor(NoteVConfig.Design.textPrimary)
                        }
                    }
                }
                .padding()
                .background(NoteVConfig.Design.surface)
                .cornerRadius(NoteVConfig.Design.cornerRadius)
            }
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(sortedSections) { section in
                Section {
                    sectionContent(section)
                } header: {
                    stickySectionHeader(section)
                }
            }
        }
    }

    // MARK: - Sticky Section Header

    private func stickySectionHeader(_ section: NoteSection) -> some View {
        HStack(spacing: 0) {
            // Left gutter (matches timeline row)
            Spacer()
                .frame(width: NoteVConfig.Design.timelineGutterWidth)

            // Rail connector with larger dot
            ZStack {
                Rectangle()
                    .fill(NoteVConfig.Design.timelineRailColor)
                    .frame(width: NoteVConfig.Design.timelineRailWidth)
                Circle()
                    .fill(section.isBookmarkSection
                        ? NoteVConfig.Design.bookmarkHighlight
                        : NoteVConfig.Design.accent)
                    .frame(width: NoteVConfig.Design.timelineSectionDotSize,
                           height: NoteVConfig.Design.timelineSectionDotSize)
            }
            .frame(width: 16)

            // Header content
            HStack(spacing: 6) {
                if section.isBookmarkSection {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                }
                Text(section.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(section.isBookmarkSection
                        ? NoteVConfig.Design.bookmarkHighlight
                        : NoteVConfig.Design.textPrimary)
                    .lineLimit(2)

                Spacer()

                if let range = section.formattedTimeRange {
                    Text(range)
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NoteVConfig.Design.surface)
                        .cornerRadius(8)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, NoteVConfig.Design.padding)
            .padding(.vertical, 10)
        }
        .background(
            NoteVConfig.Design.background.opacity(0.95)
        )
        .background(.ultraThinMaterial.opacity(0.5))
        .id("header-\(section.id)")
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SectionPositionKey.self,
                    value: [section.id: geo.frame(in: .named("timeline")).minY]
                )
            }
        )
    }

    // MARK: - Section Content

    private func sectionContent(_ section: NoteSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text content
            if !section.content.isEmpty {
                timelineRow(
                    timestamp: section.effectiveStartTime,
                    isBookmark: section.isBookmarkSection
                ) {
                    textBlock(section.content, isBookmark: section.isBookmarkSection)
                }
            }

            // Images
            ForEach(section.images) { image in
                timelineRow(
                    timestamp: image.timestamp > 0 ? image.timestamp : nil,
                    isBookmark: section.isBookmarkSection
                ) {
                    imageBlock(image)
                }
            }
        }
    }

    // MARK: - Timeline Row Wrapper

    private func timelineRow<Content: View>(
        timestamp: TimeInterval?,
        isBookmark: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left gutter: timestamp label
            VStack {
                if let ts = timestamp {
                    Text(Self.formatTime(ts))
                        .font(.caption2)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .monospacedDigit()
                }
            }
            .frame(width: NoteVConfig.Design.timelineGutterWidth, alignment: .trailing)

            // Timeline rail + dot
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(NoteVConfig.Design.timelineRailColor)
                    .frame(width: NoteVConfig.Design.timelineRailWidth)

                Circle()
                    .fill(isBookmark
                        ? NoteVConfig.Design.bookmarkHighlight
                        : NoteVConfig.Design.accent.opacity(0.6))
                    .frame(width: NoteVConfig.Design.timelineDotSize,
                           height: NoteVConfig.Design.timelineDotSize)
                    .padding(.top, 6)
            }
            .frame(width: 16)

            // Content area
            content()
                .padding(.leading, 12)
                .padding(.trailing, NoteVConfig.Design.padding)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Text Block

    private func textBlock(_ text: String, isBookmark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isBookmark {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                    .lineSpacing(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(NoteVConfig.Design.bookmarkHighlight.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(NoteVConfig.Design.bookmarkHighlight)
                            .frame(width: 3)
                    }
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            } else {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                    .lineSpacing(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Image Block

    private func imageBlock(_ image: NoteImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sid = sessionId,
               let imageData = imageStore.loadImage(filename: image.filename, sessionId: sid),
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipped()
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            } else {
                RoundedRectangle(cornerRadius: NoteVConfig.Design.cornerRadius)
                    .fill(NoteVConfig.Design.surface)
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    )
            }

            HStack(spacing: 8) {
                if !image.caption.isEmpty {
                    Text(image.caption)
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .italic()
                }
                Spacer()
                if image.timestamp > 0 {
                    Text(Self.formatTime(image.timestamp))
                        .font(.caption2)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Floating Timestamp Pill

    private var floatingTimestampPill: some View {
        Group {
            if let section = currentSection, let range = section.formattedTimeRange {
                Text(range)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(NoteVConfig.Design.surface)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: currentSectionId)
    }

    // MARK: - TOC Button

    private func tocButton(proxy: ScrollViewProxy) -> some View {
        Button {
            showTOC = true
        } label: {
            Image(systemName: "list.bullet")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(NoteVConfig.Design.textPrimary)
                .frame(width: 44, height: 44)
                .background(NoteVConfig.Design.surface)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .padding(.trailing, NoteVConfig.Design.padding)
        .padding(.bottom, NoteVConfig.Design.padding)
        .sheet(isPresented: $showTOC) {
            TimelineTOCSheet(sections: sortedSections) { section in
                withAnimation {
                    proxy.scrollTo("header-\(section.id)", anchor: .top)
                }
            }
        }
    }

    // MARK: - Footer

    private var generationFooter: some View {
        HStack {
            Spacer()
            Text("Generated by \(notes.modelUsed) via NoteV")
                .font(.caption2)
                .foregroundColor(NoteVConfig.Design.textSecondary)
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.top, 20)
    }

    // MARK: - Helpers

    static func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Section Position Preference Key

struct SectionPositionKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        TimelineNoteView(notes: StructuredNotes(
            title: "Sample Lecture Notes",
            summary: "This is a preview of generated notes with timeline.",
            sections: [
                NoteSection(title: "Introduction", content: "Sample content here about the introduction to the topic...", order: 0, startTime: 0, endTime: 120),
                NoteSection(title: "Main Concepts", content: "The professor discussed key concepts including X, Y, and Z.", order: 1, startTime: 120, endTime: 450),
                NoteSection(title: "Bookmarked Highlights", content: "Important moment noted by student.", order: 2, startTime: 300, endTime: 360, isBookmarkSection: true)
            ],
            keyTakeaways: ["First key point", "Second key point"]
        ))
    }
    .background(NoteVConfig.Design.background)
}
