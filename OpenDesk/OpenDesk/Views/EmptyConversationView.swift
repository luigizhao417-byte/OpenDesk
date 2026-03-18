import SwiftUI

struct EmptyConversationView: View {
    @EnvironmentObject private var appState: AppState

    let openTaskCenter: () -> Void
    let openAgentCenter: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.36), AppTheme.warning.opacity(0.26)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)

                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text(appState.text("empty.title"))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(appState.configuration.isComplete ? appState.text("empty.readyDescription") : appState.text("empty.setupDescription"))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 14) {
                Button {
                    openAgentCenter()
                } label: {
                    Label(appState.text("empty.openAgent"), systemImage: "terminal")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.warning.opacity(0.84))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    openTaskCenter()
                } label: {
                    Label(appState.text("empty.openTaskCenter"), systemImage: "flag.checkered.2.crossed")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.accent)
                        )
                }
                .buttonStyle(.plain)

                SettingsLink {
                    Label(appState.text("empty.openSettings"), systemImage: "gearshape")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }
}
