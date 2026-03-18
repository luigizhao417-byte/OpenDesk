import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var apiURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var revealAPIKey = false
    @State private var knowledgeTitle = ""
    @State private var knowledgeContent = ""
    @State private var editingKnowledgeID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(appState.text("settings.language.title"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("settings.language.subtitle"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("", selection: Binding(
                        get: { appState.appLanguage },
                        set: { appState.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(22)
                .background(AppTheme.panelGradient)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 16) {
                    Text(appState.text("settings.onboarding.title"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("settings.onboarding.subtitle"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        appState.reopenOnboarding()
                    } label: {
                        Label(appState.text("settings.onboarding.reopen"), systemImage: "sparkles.rectangle.stack.fill")
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
                .padding(22)
                .background(AppTheme.panelGradient)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.text("settings.api.title"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("settings.api.subtitle"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 18) {
                    settingField(
                        title: "API URL",
                        hint: appState.text("settings.api.urlHint"),
                        text: $apiURL
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("API Key")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))

                            Spacer()

                            Button(revealAPIKey ? appState.text("settings.api.hide") : appState.text("settings.api.reveal")) {
                                revealAPIKey.toggle()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        }

                        Group {
                            if revealAPIKey {
                                TextField("sk-...", text: $apiKey)
                            } else {
                                SecureField("sk-...", text: $apiKey)
                            }
                        }
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
                    }

                    settingField(
                        title: appState.text("settings.modelName"),
                        hint: appState.text("settings.modelNameHint"),
                        text: $modelName
                    )
                }
                .padding(22)
                .background(AppTheme.panelGradient)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )

                HStack(spacing: 14) {
                    Button {
                        appState.updateConfiguration(url: apiURL, key: apiKey, model: modelName)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray.and.arrow.down.fill")
                            Text(appState.text("settings.api.save"))
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppTheme.accent)
                        )
                    }
                    .buttonStyle(.plain)

                    Text(appState.configuration.isComplete ? appState.text("settings.api.complete") : appState.text("settings.api.incomplete"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.text("settings.compatibility"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(appState.text("settings.compatibility.1"))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(appState.text("settings.compatibility.2"))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(appState.text("settings.compatibility.3"))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))

                VStack(alignment: .leading, spacing: 16) {
                    Text(appState.text("settings.knowledge.title"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("settings.knowledge.subtitle"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    settingField(
                        title: appState.text("settings.knowledge.entryTitle"),
                        hint: appState.text("settings.knowledge.entryHint"),
                        text: $knowledgeTitle
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text(appState.text("settings.knowledge.content"))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))

                        TextEditor(text: $knowledgeContent)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(.white)
                            .padding(12)
                            .frame(height: 160)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(AppTheme.border, lineWidth: 1)
                                    )
                            )
                    }

                    HStack(spacing: 12) {
                        Button {
                            if appState.saveKnowledgeBaseEntry(
                                id: editingKnowledgeID,
                                title: knowledgeTitle,
                                content: knowledgeContent
                            ) {
                                editingKnowledgeID = nil
                                knowledgeTitle = ""
                                knowledgeContent = ""
                            }
                        } label: {
                            Label(editingKnowledgeID == nil ? appState.text("settings.knowledge.save") : appState.text("settings.knowledge.update"), systemImage: "books.vertical.fill")
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
                            editingKnowledgeID = nil
                            knowledgeTitle = ""
                            knowledgeContent = ""
                        } label: {
                            Label(appState.text("settings.knowledge.clearEditor"), systemImage: "eraser")
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

                        Spacer()

                        Button(role: .destructive) {
                            appState.clearKnowledgeBase()
                        } label: {
                            Label(appState.text("settings.knowledge.clearAll"), systemImage: "trash")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.red.opacity(0.25))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if appState.recentKnowledgeBaseEntries.isEmpty {
                        Text(appState.text("settings.knowledge.empty"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    } else {
                        ForEach(appState.recentKnowledgeBaseEntries) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(entry.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Spacer()

                                    Text(entry.updatedAt, style: .relative)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.tertiaryText)
                                }

                                Text(entry.content)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 12) {
                                    Button {
                                        editingKnowledgeID = entry.id
                                        knowledgeTitle = entry.title
                                        knowledgeContent = entry.content
                                    } label: {
                                        Label(appState.text("common.edit"), systemImage: "square.and.pencil")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                            .foregroundStyle(.white)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.white.opacity(0.05))
                                            )
                                    }
                                    .buttonStyle(.plain)

                                    Button(role: .destructive) {
                                        appState.deleteKnowledgeBaseEntry(entry)
                                    } label: {
                                        Label(appState.text("common.delete"), systemImage: "trash")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                            .foregroundStyle(.white)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color.red.opacity(0.25))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(AppTheme.border, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text(appState.text("settings.memory.title"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("settings.memory.subtitle"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    if appState.recentMemories.isEmpty {
                        Text(appState.text("settings.memory.empty"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    } else {
                        ForEach(appState.recentMemories) { memory in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(memory.content)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(appState.text("settings.memory.source", memory.source, appState.relativeTimeString(since: memory.updatedAt)))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.tertiaryText)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    appState.removeMemory(memory)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(10)
                                        .foregroundStyle(.white)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.red.opacity(0.25))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(AppTheme.border, lineWidth: 1)
                                    )
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            appState.clearLearnedMemories()
                        } label: {
                            Label(appState.text("settings.memory.clear"), systemImage: "brain.head.profile")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.red.opacity(0.25))
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text(appState.text("settings.data.title"))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(appState.text("settings.data.subtitle"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(appState.text("settings.data.kbNote"))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(role: .destructive) {
                        appState.clearLocalDataKeepingAPI()
                    } label: {
                        Label(appState.text("settings.data.clear"), systemImage: "trash.circle.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.red.opacity(0.28))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [AppTheme.sidebarBottom, AppTheme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear(perform: syncFromState)
    }

    private func settingField(title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            TextField(hint, text: text)
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
        }
    }

    private func syncFromState() {
        apiURL = appState.configuration.apiURL
        apiKey = appState.configuration.apiKey
        modelName = appState.configuration.modelName
        knowledgeTitle = ""
        knowledgeContent = ""
        editingKnowledgeID = nil
    }
}
