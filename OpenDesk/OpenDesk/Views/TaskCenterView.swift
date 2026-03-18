import SwiftUI

struct TaskCenterView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @Binding var prefillText: String

    @State private var taskTitle = ""
    @State private var taskDetail = ""
    @State private var didSeedPrefill = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.text("taskCenter.title"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("taskCenter.subtitle"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(12)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(appState.text("taskCenter.newTask"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))

                TextField(appState.text("taskCenter.taskTitleHint"), text: $taskTitle)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                    )

                TextEditor(text: $taskDetail)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                    )

                HStack {
                    Text(appState.text("taskCenter.prefillTip"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    Spacer()

                    Button {
                        if appState.addTask(title: taskTitle, detail: taskDetail) {
                            if taskDetail.trimmingCharacters(in: .whitespacesAndNewlines) == prefillText.trimmingCharacters(in: .whitespacesAndNewlines) {
                                prefillText = ""
                            }
                            taskTitle = ""
                            taskDetail = ""
                        }
                    } label: {
                        Label(appState.text("taskCenter.createTask"), systemImage: "plus.circle.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
            .appCard(fill: AppTheme.panelSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    taskSection(title: appState.text("task.section.pending"), tasks: appState.pendingTasks)
                    taskSection(title: appState.text("task.section.completed"), tasks: appState.completedTasks)
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
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
            seedPrefillIfNeeded()
        }
    }

    @ViewBuilder
    private func taskSection(title: String, tasks: [AgentTask]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if tasks.isEmpty {
                Text(title == appState.text("task.section.pending") ? appState.text("task.none.pending") : appState.text("task.none.completed"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(tasks) { task in
                        TaskRowView(
                            task: task,
                            linkedConversationTitle: appState.conversationTitle(for: task.linkedConversationID),
                            onRun: {
                                _ = appState.runTask(task)
                            },
                            onToggleComplete: {
                                appState.toggleTaskCompletion(task)
                            },
                            onDelete: {
                                appState.deleteTask(task)
                            }
                        )
                    }
                }
            }
        }
    }

    private func seedPrefillIfNeeded() {
        guard !didSeedPrefill else {
            return
        }

        let trimmedPrefill = prefillText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefill.isEmpty else {
            didSeedPrefill = true
            return
        }

        taskDetail = trimmedPrefill
        taskTitle = AppState.condensedTitle(from: trimmedPrefill, fallback: appState.text("task.newTaskFallback"))
        didSeedPrefill = true
    }
}
