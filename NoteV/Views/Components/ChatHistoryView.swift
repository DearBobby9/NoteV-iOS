import SwiftUI

// MARK: - ChatHistoryView

/// Shows list of past chat conversations. Tap to select, swipe to delete.
struct ChatHistoryView: View {
    var onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var conversations: [ChatConversation] = []

    var body: some View {
        NavigationView {
            ZStack {
                NoteVConfig.Design.background
                    .ignoresSafeArea()

                if conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(NoteVConfig.Design.accent)
                }
            }
            .onAppear { loadConversations() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.5))
            Text("No chat history yet")
                .font(.subheadline)
                .foregroundColor(NoteVConfig.Design.textSecondary)
        }
    }

    private var conversationList: some View {
        List {
            ForEach(conversations) { conversation in
                Button {
                    onSelect(conversation.id)
                    dismiss()
                } label: {
                    conversationRow(conversation)
                }
                .listRowBackground(NoteVConfig.Design.surface)
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func conversationRow(_ conversation: ChatConversation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.callout)
                .foregroundColor(NoteVConfig.Design.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.callout.weight(.medium))
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(conversation.lastMessageAt, style: .relative)
                    Text("·")
                    Text("\(conversation.messageCount) messages")
                }
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private func loadConversations() {
        conversations = ChatStore.shared.listConversations()
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversation = conversations[index]
            ChatStore.shared.deleteConversation(id: conversation.id)
        }
        conversations.remove(atOffsets: offsets)
    }
}
