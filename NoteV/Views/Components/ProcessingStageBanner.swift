import SwiftUI

// MARK: - ProcessingStageBanner

/// Global progress banner shown during post-recording processing on all result tabs.
struct ProcessingStageBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isPostProcessing, let label = appState.processingStageLabel {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(NoteVConfig.Design.surface)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.top, 8)
        } else if !appState.processingWarnings.isEmpty, appState.sessionStatus == .complete {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(appState.processingWarnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: warningIcon(for: warning))
                            .foregroundColor(warningColor(for: warning))
                        Text(warning)
                            .font(.subheadline)
                            .foregroundColor(NoteVConfig.Design.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .background(NoteVConfig.Design.surface)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.top, 8)
        }
    }

    private func warningIcon(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("failed") {
            return "exclamationmark.triangle.fill"
        }
        return "info.circle.fill"
    }

    private func warningColor(for message: String) -> Color {
        if message.localizedCaseInsensitiveContains("failed") {
            return .orange
        }
        return NoteVConfig.Design.textSecondary
    }
}

// MARK: - Preview

#Preview {
    ProcessingStageBanner()
        .environmentObject(AppState())
        .background(NoteVConfig.Design.background)
}
