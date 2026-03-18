import AppKit
import SwiftUI

struct AgentCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @Binding var prefillGoal: String

    @State private var goalText = ""
    @State private var didSeedGoal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            workspaceCard
            goalCard
            logCard
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [AppTheme.canvas, AppTheme.sidebarBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            seedGoalIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(appState.text("agent.title"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(appState.text("agent.subtitle"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)

                Text(appState.text("agent.note"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.text("agent.workspace"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(appState.workspacePath ?? appState.text("agent.workspace.none"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(appState.workspacePath == nil ? AppTheme.secondaryText : .white.opacity(0.88))
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button {
                    _ = appState.createDesktopWorkspace()
                } label: {
                    Label(appState.text("agent.useDesktop"), systemImage: "desktopcomputer")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.accent)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    pickWorkspace()
                } label: {
                    Label(appState.text("agent.chooseFolder"), systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.openWorkspaceInFinder()
                } label: {
                    Label(appState.text("agent.openFinder"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .disabled(appState.workspacePath == nil)
            }
        }
        .padding(22)
        .appCard(fill: AppTheme.panelSecondary)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.text("agent.goal"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            TextEditor(text: $goalText)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(12)
                .frame(height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                )

            Text(appState.text("agent.goalExample"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            if let summary = appState.agentLastSummary, !summary.isEmpty {
                Text(appState.text("agent.lastSummary", summary))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button {
                    if appState.runAgent(goal: goalText) {
                        prefillGoal = goalText
                    }
                } label: {
                    Label(appState.isAgentRunning ? appState.text("agent.running") : appState.text("agent.start"), systemImage: "play.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(appState.isAgentRunning ? AppTheme.accentSoft : AppTheme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(appState.isAgentRunning)

                if appState.isAgentRunning {
                    Button {
                        appState.cancelAgentRun()
                    } label: {
                        Label(appState.text("composer.stop"), systemImage: "stop.fill")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.red.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    appState.clearAgentLogs()
                } label: {
                    Label(appState.text("agent.clearLogs"), systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .appCard(fill: AppTheme.panelSecondary)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(appState.text("agent.logs"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if appState.isAgentRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if appState.agentLogs.isEmpty {
                        Text(appState.text("agent.noLogs"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(appState.agentLogs) { entry in
                            logRow(entry)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCard(fill: AppTheme.panel)
    }

    private func logRow(_ entry: AgentLogEntry) -> some View {
        let color: Color = {
            switch entry.level {
            case .info:
                return AppTheme.accent
            case .success:
                return AppTheme.success
            case .warning:
                return AppTheme.warning
            case .error:
                return Color.red
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Text(entry.detail)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(color.opacity(0.55), lineWidth: 1)
                )
        )
    }

    private func seedGoalIfNeeded() {
        guard !didSeedGoal else {
            return
        }

        let trimmed = prefillGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            goalText = trimmed
        }
        didSeedGoal = true
    }

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = appState.text("agent.pickWorkspacePrompt")

        if panel.runModal() == .OK, let url = panel.url {
            appState.setWorkspace(url)
        }
    }
}
