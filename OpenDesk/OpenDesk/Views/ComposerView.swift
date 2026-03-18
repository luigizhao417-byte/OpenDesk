import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var appState: AppState

    @Binding var draftText: String

    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onOpenTasks: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(appState.text("composer.title"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Text(isSending ? appState.text("composer.streaming") : appState.text("composer.multiTurn"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            TextEditor(text: $draftText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(14)
                .frame(minHeight: 96, maxHeight: 146)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )

            HStack(spacing: 12) {
                Button {
                    onOpenTasks()
                } label: {
                    Label(appState.text("composer.task"), systemImage: "flag.checkered.2.crossed")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                if isSending {
                    Button {
                        onCancel()
                    } label: {
                        Label(appState.text("composer.stop"), systemImage: "stop.fill")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.red.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onSend()
                } label: {
                    HStack(spacing: 10) {
                        Text(appState.text("composer.send"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canSend ? AppTheme.accent : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend || isSending)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(18)
        .appCard(fill: AppTheme.panelSecondary)
    }
}
