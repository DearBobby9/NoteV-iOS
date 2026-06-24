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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                Text(appState.processingWarnings.joined(separator: " "))
                    .font(.caption)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(NoteVConfig.Design.surface)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.top, 8)
        }
    }
}

// MARK: - Preview

#Preview {
    ProcessingStageBanner()
        .environmentObject(AppState())
        .background(NoteVConfig.Design.background)
}
