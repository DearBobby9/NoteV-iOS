import SwiftUI

// MARK: - ProcessingStageBanner

/// Compact progress banner during post-recording processing; includes optional cancel action.
struct ProcessingStageBanner: View {
    @EnvironmentObject var appState: AppState
    var onCancel: (() -> Void)?

    var body: some View {
        if appState.isPostProcessing, let label = appState.processingStageLabel {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                    .scaleEffect(0.85)

                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(NoteVConfig.Design.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let onCancel {
                    Button("Stop", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NoteVConfig.Design.surface)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.top, 4)
        } else if !appState.processingWarnings.isEmpty, appState.sessionStatus == .complete {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(appState.processingWarnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: warningIcon(for: warning))
                            .font(.caption)
                            .foregroundColor(warningColor(for: warning))
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(NoteVConfig.Design.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NoteVConfig.Design.surface)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.top, 4)
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
    ProcessingStageBanner(onCancel: {})
        .environmentObject(AppState())
        .background(NoteVConfig.Design.background)
}
