import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var appLanguage: AppLanguage
    @Published var configuration: APIConfiguration
    @Published var conversations: [ChatConversation]
    @Published var tasks: [AgentTask]
    @Published var selectedConversationID: UUID?
    @Published var workspacePath: String?
    @Published var learnedMemories: [LearnedMemoryItem]
    @Published var knowledgeBaseEntries: [KnowledgeBaseEntry]
    @Published var agentLogs: [AgentLogEntry] = []
    @Published var agentLastSummary: String?
    @Published var isLoading = false
    @Published var isAgentRunning = false
    @Published var isOnboardingPresented: Bool
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let persistenceStore: PersistenceStore
    private let aiService: AIService
    private let workspaceService: WorkspaceService
    private let commandService: LocalCommandService
    private let projectValidator: ProjectValidator
    private let userDefaults: UserDefaults
    private lazy var agentAutomationService = AgentAutomationService(
        aiService: aiService,
        workspaceService: workspaceService,
        commandService: commandService,
        projectValidator: projectValidator
    )

    private var activeResponseTask: Task<Void, Never>?
    private var activeAgentTask: Task<Void, Never>?

    private static let languagePreferenceKey = "OpenDesk.appLanguage"
    private static let onboardingCompletedKey = "OpenDesk.onboardingCompleted"
    private static let legacyLanguagePreferenceKey = "AgentDesk.appLanguage"
    private static let legacyOnboardingCompletedKey = "AgentDesk.onboardingCompleted"

    init(
        persistenceStore: PersistenceStore = .shared,
        aiService: AIService = AIService(),
        workspaceService: WorkspaceService = WorkspaceService(),
        commandService: LocalCommandService = LocalCommandService(),
        projectValidator: ProjectValidator = ProjectValidator(),
        userDefaults: UserDefaults = .standard
    ) {
        self.persistenceStore = persistenceStore
        self.aiService = aiService
        self.workspaceService = workspaceService
        self.commandService = commandService
        self.projectValidator = projectValidator
        self.userDefaults = userDefaults

        let savedLanguage = (
            userDefaults.string(forKey: Self.languagePreferenceKey)
            ?? userDefaults.string(forKey: Self.legacyLanguagePreferenceKey)
        )
            .flatMap(AppLanguage.init(rawValue:))
        appLanguage = savedLanguage ?? AppLanguage.bestMatch()
        let hasCompletedOnboarding = (
            userDefaults.object(forKey: Self.onboardingCompletedKey) as? Bool
            ?? userDefaults.object(forKey: Self.legacyOnboardingCompletedKey) as? Bool
            ?? false
        )
        isOnboardingPresented = !hasCompletedOnboarding

        let snapshot = persistenceStore.load()
        configuration = snapshot.configuration
        conversations = snapshot.conversations.sorted(by: { $0.updatedAt > $1.updatedAt })
        tasks = snapshot.tasks.sorted(by: { $0.updatedAt > $1.updatedAt })
        selectedConversationID = snapshot.selectedConversationID
        workspacePath = snapshot.workspacePath
        learnedMemories = (snapshot.learnedMemories ?? []).sorted(by: { $0.updatedAt > $1.updatedAt })
        knowledgeBaseEntries = (snapshot.knowledgeBaseEntries ?? []).sorted(by: { $0.updatedAt > $1.updatedAt })

        if workspacePath == nil, let defaultWorkspaceURL = try? workspaceService.createDesktopWorkspace() {
            workspacePath = defaultWorkspaceURL.path
        }

        if conversations.isEmpty {
            let conversation = ChatConversation(title: text("conversation.new"))
            conversations = [conversation]
            selectedConversationID = conversation.id
            persistSafely()
        } else if selectedConversation == nil {
            selectedConversationID = conversations.first?.id
        }
    }

    deinit {
        activeResponseTask?.cancel()
        activeAgentTask?.cancel()
    }

    var selectedConversation: ChatConversation? {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return nil
        }

        return conversations[index]
    }

    var workspaceURL: URL? {
        guard let workspacePath else {
            return nil
        }
        return URL(fileURLWithPath: workspacePath, isDirectory: true)
    }

    var appLocale: Locale {
        appLanguage.locale
    }

    var hasCompletedOnboarding: Bool {
        userDefaults.object(forKey: Self.onboardingCompletedKey) as? Bool ?? false
    }

    var pendingTasks: [AgentTask] {
        tasks
            .filter { $0.status != .completed }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var recentMemories: [LearnedMemoryItem] {
        learnedMemories
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(12)
            .map { $0 }
    }

    var recentKnowledgeBaseEntries: [KnowledgeBaseEntry] {
        knowledgeBaseEntries
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(12)
            .map { $0 }
    }

    var completedTasks: [AgentTask] {
        tasks
            .filter { $0.status == .completed }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var pendingTaskCount: Int {
        tasks.filter { $0.status != .completed }.count
    }

    @discardableResult
    func createConversationAndSelect(title: String? = nil, sourceTaskID: UUID? = nil) -> UUID {
        let conversation = ChatConversation(title: title ?? text("conversation.new"), sourceTaskID: sourceTaskID)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        persistSafely()
        return conversation.id
    }

    func selectConversation(_ conversation: ChatConversation) {
        selectedConversationID = conversation.id
        persistSafely()
    }

    func deleteConversation(_ conversation: ChatConversation) {
        if isLoading, selectedConversationID == conversation.id {
            cancelStreaming()
        }

        conversations.removeAll { $0.id == conversation.id }

        for index in tasks.indices where tasks[index].linkedConversationID == conversation.id {
            tasks[index].linkedConversationID = nil
            tasks[index].updatedAt = Date()
        }

        if conversations.isEmpty {
            let replacement = ChatConversation(title: text("conversation.new"))
            conversations = [replacement]
            selectedConversationID = replacement.id
        } else if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }

        persistSafely()
    }

    func updateConfiguration(url: String, key: String, model: String) {
        configuration = APIConfiguration(
            apiURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        statusMessage = text("status.configurationSaved")
        persistSafely(reportErrors: true)
    }

    func setWorkspace(_ url: URL) {
        workspacePath = url.standardizedFileURL.path
        statusMessage = text("status.workspaceConnected")
        persistSafely(reportErrors: true)
    }

    @discardableResult
    func createDesktopWorkspace(named name: String = "OpenDeskWorkspace") -> Bool {
        do {
            let url = try workspaceService.createDesktopWorkspace(named: name)
            setWorkspace(url)
            statusMessage = text("status.desktopWorkspaceReady")
            return true
        } catch {
            errorMessage = presentableErrorMessage(for: error)
            return false
        }
    }

    func openWorkspaceInFinder() {
        guard let workspaceURL else {
            errorMessage = text("error.selectWorkspaceFirst")
            return
        }

        NSWorkspace.shared.open(workspaceURL)
    }

    func dismissError() {
        errorMessage = nil
    }

    func clearStatus() {
        statusMessage = nil
    }

    func clearAgentLogs() {
        agentLogs.removeAll()
        agentLastSummary = nil
    }

    func setLanguage(_ language: AppLanguage) {
        guard appLanguage != language else {
            return
        }

        appLanguage = language
        userDefaults.set(language.rawValue, forKey: Self.languagePreferenceKey)
        persistSafely()
    }

    func completeOnboarding() {
        userDefaults.set(true, forKey: Self.onboardingCompletedKey)
        isOnboardingPresented = false
        statusMessage = text("status.onboardingComplete")
    }

    func reopenOnboarding() {
        isOnboardingPresented = true
    }

    func dismissOnboarding() {
        isOnboardingPresented = false
    }

    func removeMemory(_ memory: LearnedMemoryItem) {
        learnedMemories.removeAll { $0.id == memory.id }
        persistSafely()
    }

    func clearLearnedMemories() {
        learnedMemories.removeAll()
        persistSafely()
    }

    @discardableResult
    func saveKnowledgeBaseEntry(id: UUID?, title: String, content: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            errorMessage = text("error.kbEmpty")
            return false
        }

        if let id, let index = knowledgeBaseEntries.firstIndex(where: { $0.id == id }) {
            knowledgeBaseEntries[index].title = trimmedTitle
            knowledgeBaseEntries[index].content = trimmedContent
            knowledgeBaseEntries[index].updatedAt = Date()
        } else {
            knowledgeBaseEntries.insert(
                KnowledgeBaseEntry(title: trimmedTitle, content: trimmedContent),
                at: 0
            )
        }

        knowledgeBaseEntries.sort(by: { $0.updatedAt > $1.updatedAt })
        statusMessage = text("status.kbSaved")
        persistSafely()
        return true
    }

    func deleteKnowledgeBaseEntry(_ entry: KnowledgeBaseEntry) {
        knowledgeBaseEntries.removeAll { $0.id == entry.id }
        persistSafely()
    }

    func clearKnowledgeBase() {
        knowledgeBaseEntries.removeAll()
        persistSafely()
    }

    func clearLocalDataKeepingAPI() {
        activeResponseTask?.cancel()
        activeAgentTask?.cancel()

        isLoading = false
        isAgentRunning = false
        tasks.removeAll()
        agentLogs.removeAll()
        agentLastSummary = nil
        learnedMemories.removeAll()
        knowledgeBaseEntries.removeAll()
        workspacePath = nil

        let conversation = ChatConversation(title: text("conversation.new"))
        conversations = [conversation]
        selectedConversationID = conversation.id
        statusMessage = text("status.localDataCleared")
        persistSafely()
    }

    @discardableResult
    func sendMessage(_ draft: String) -> Bool {
        learnFromUserInput(draft, source: "user_message")
        return startAssistantRun(
            userInput: draft,
            preferredTitle: nil,
            sourceTaskID: nil,
            forceNewConversation: false
        )
    }

    func cancelStreaming() {
        statusMessage = text("status.stopping")
        activeResponseTask?.cancel()
    }

    @discardableResult
    func addTask(title: String, detail: String) -> Bool {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.isEmpty else {
            errorMessage = text("error.taskEmpty")
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? Self.condensedTitle(from: trimmedDetail, fallback: text("task.newTaskFallback")) : trimmedTitle

        let task = AgentTask(title: finalTitle, detail: trimmedDetail)
        tasks.insert(task, at: 0)
        statusMessage = text("status.taskCreated")
        learnFromUserInput(trimmedDetail, source: "task")
        persistSafely()
        return true
    }

    func deleteTask(_ task: AgentTask) {
        if task.status == .running {
            cancelStreaming()
        }

        tasks.removeAll { $0.id == task.id }
        persistSafely()
    }

    func toggleTaskCompletion(_ task: AgentTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].status = tasks[index].status == .completed ? .pending : .completed
        tasks[index].updatedAt = Date()
        persistSafely()
    }

    @discardableResult
    func runTask(_ task: AgentTask) -> Bool {
        guard !isAgentRunning else {
            errorMessage = text("error.agentRunning")
            return false
        }

        guard !isLoading else {
            errorMessage = text("error.replyRunning")
            return false
        }

        let shouldUseFreshConversation: Bool
        if let currentConversation = selectedConversation {
            shouldUseFreshConversation = !currentConversation.messages.isEmpty && currentConversation.sourceTaskID != task.id
        } else {
            shouldUseFreshConversation = true
        }

        let prompt = """
        \(text("prompt.task.execute"))

        \(text("prompt.task.title"))
        \(task.title)

        \(text("prompt.task.detail"))
        \(task.detail)

        \(text("prompt.task.requirements"))
        """

        return startAssistantRun(
            userInput: prompt,
            preferredTitle: task.title,
            sourceTaskID: task.id,
            forceNewConversation: shouldUseFreshConversation
        )
    }

    @discardableResult
    func runAgent(goal: String) -> Bool {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedGoal.isEmpty else {
            errorMessage = text("error.agentGoalEmpty")
            return false
        }

        guard configuration.isComplete else {
            errorMessage = text("error.apiIncomplete")
            return false
        }

        guard !isLoading else {
            errorMessage = text("error.chatRunning")
            return false
        }

        guard !isAgentRunning else {
            errorMessage = text("error.agentAlreadyRunning")
            return false
        }

        let targetWorkspaceURL: URL
        if let workspaceURL {
            targetWorkspaceURL = workspaceURL
        } else {
            guard createDesktopWorkspace() else {
                return false
            }
            guard let createdWorkspaceURL = workspaceURL else {
                errorMessage = text("error.createWorkspaceFailed")
                return false
            }
            targetWorkspaceURL = createdWorkspaceURL
        }

        agentLogs.removeAll()
        agentLastSummary = nil
        addAgentLog(level: .info, title: text("agent.log.goal"), detail: trimmedGoal)
        addAgentLog(level: .info, title: text("agent.log.workspace"), detail: targetWorkspaceURL.path)
        learnFromUserInput(trimmedGoal, source: "agent_goal", force: true)

        let currentConfiguration = configuration
        let automationService = agentAutomationService

        isAgentRunning = true
        statusMessage = text("status.agentRunning")
        persistSafely()

        activeAgentTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await automationService.run(
                    goal: trimmedGoal,
                    workspaceURL: targetWorkspaceURL,
                    configuration: currentConfiguration,
                    memoryContext: self.assistantKnowledgeContextText,
                    language: self.appLanguage
                ) { entry in
                    await MainActor.run {
                        self.agentLogs.append(entry)
                    }
                } onLearnedMemory: { memoryNote in
                    await MainActor.run {
                        self.storeMemory(memoryNote, source: "agent_remember")
                    }
                }

                await MainActor.run {
                    self.isAgentRunning = false
                    self.activeAgentTask = nil
                    self.agentLastSummary = result.message
                    self.statusMessage = self.text("status.agentDone")
                    self.persistSafely()
                    self.appendAgentRunToConversation(
                        goal: trimmedGoal,
                        summary: result.message,
                        workspacePath: targetWorkspaceURL.path,
                        validationResult: result.validationResult
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isAgentRunning = false
                    self.activeAgentTask = nil
                    self.statusMessage = self.text("status.agentStopped")
                    self.addAgentLog(
                        level: .warning,
                        title: self.text("agent.log.interrupted.title"),
                        detail: self.text("agent.log.interrupted.detail")
                    )
                    self.persistSafely()
                }
            } catch {
                await MainActor.run {
                    self.isAgentRunning = false
                    self.activeAgentTask = nil
                    self.statusMessage = nil
                    let message = self.presentableErrorMessage(for: error)
                    self.errorMessage = message
                    self.addAgentLog(level: .error, title: self.text("agent.log.runFailed"), detail: message)
                    self.persistSafely()
                }
            }
        }

        return true
    }

    func cancelAgentRun() {
        statusMessage = text("status.stoppingAgent")
        activeAgentTask?.cancel()
    }

    func conversationTitle(for id: UUID?) -> String? {
        guard let id else {
            return nil
        }

        return conversations.first(where: { $0.id == id })?.title
    }

    static func condensedTitle(from text: String, fallback: String = "New Chat") -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !singleLine.isEmpty else {
            return fallback
        }

        return String(singleLine.prefix(22))
    }

    @discardableResult
    private func startAssistantRun(
        userInput: String,
        preferredTitle: String?,
        sourceTaskID: UUID?,
        forceNewConversation: Bool
    ) -> Bool {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedInput.isEmpty else {
            return false
        }

        guard !isAgentRunning else {
            errorMessage = text("error.agentRunning")
            return false
        }

        guard configuration.isComplete else {
            errorMessage = text("error.settingsFirst")
            return false
        }

        let conversationID: UUID
        if forceNewConversation || selectedConversation == nil {
            conversationID = createConversationAndSelect(
                title: preferredTitle ?? Self.condensedTitle(from: trimmedInput, fallback: text("conversation.new")),
                sourceTaskID: sourceTaskID
            )
        } else {
            conversationID = selectedConversation!.id
            prepareConversationIfNeeded(
                conversationID: conversationID,
                preferredTitle: preferredTitle,
                sourceTaskID: sourceTaskID,
                firstInput: trimmedInput
            )
        }

        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        appendMessage(userMessage, to: conversationID)

        let assistantPlaceholder = ChatMessage(role: .assistant, content: "")
        appendMessage(assistantPlaceholder, to: conversationID)

        if let sourceTaskID {
            updateTask(
                id: sourceTaskID,
                status: .running,
                linkedConversationID: conversationID,
                lastError: nil
            )
        }

        let requestMessages = makeRequestMessages(for: conversationID, excluding: assistantPlaceholder.id)
        let currentConfiguration = configuration
        let currentAIService = aiService

        isLoading = true
        errorMessage = nil
        statusMessage = text("status.generatingReply")
        persistSafely()

        activeResponseTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let finalText = try await currentAIService.streamChat(
                    configuration: currentConfiguration,
                    messages: requestMessages
                ) { chunk in
                    await MainActor.run {
                        self.appendAssistantDelta(chunk, conversationID: conversationID, messageID: assistantPlaceholder.id)
                    }
                }

                await MainActor.run {
                    self.isLoading = false
                    self.activeResponseTask = nil
                    self.statusMessage = self.text("status.replyDone")
                    self.touchConversation(conversationID)

                    if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.replaceMessageContentIfNeeded(
                            conversationID: conversationID,
                            messageID: assistantPlaceholder.id,
                            content: self.text("error.emptyModelResponse")
                        )
                    }

                    if let sourceTaskID {
                        self.updateTask(
                            id: sourceTaskID,
                            status: .completed,
                            linkedConversationID: conversationID,
                            lastError: nil
                        )
                    }

                    self.persistSafely()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoading = false
                    self.activeResponseTask = nil
                    self.statusMessage = self.text("status.replyStopped")
                    self.removeMessageIfEmpty(conversationID: conversationID, messageID: assistantPlaceholder.id)

                    if let sourceTaskID {
                        self.updateTask(
                            id: sourceTaskID,
                            status: .pending,
                            linkedConversationID: conversationID,
                            lastError: self.text("error.taskCancelled")
                        )
                    }

                    self.persistSafely()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.activeResponseTask = nil
                    self.statusMessage = nil
                    let message = self.presentableErrorMessage(for: error)
                    self.errorMessage = message
                    self.removeMessageIfEmpty(conversationID: conversationID, messageID: assistantPlaceholder.id)

                    if let sourceTaskID {
                        self.updateTask(
                            id: sourceTaskID,
                            status: .pending,
                            linkedConversationID: conversationID,
                            lastError: message
                        )
                    }

                    self.persistSafely()
                }
            }
        }

        return true
    }

    private func prepareConversationIfNeeded(
        conversationID: UUID,
        preferredTitle: String?,
        sourceTaskID: UUID?,
        firstInput: String
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        if conversations[index].messages.isEmpty {
            conversations[index].title = preferredTitle ?? Self.condensedTitle(from: firstInput, fallback: text("conversation.new"))
        }

        if conversations[index].sourceTaskID == nil {
            conversations[index].sourceTaskID = sourceTaskID
        }

        conversations[index].updatedAt = Date()
        sortConversations()
    }

    private func appendMessage(_ message: ChatMessage, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        sortConversations()
    }

    private func appendAssistantDelta(_ delta: String, conversationID: UUID, messageID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        conversations[conversationIndex].messages[messageIndex].content.append(delta)
        conversations[conversationIndex].updatedAt = Date()
        sortConversations()
    }

    private func replaceMessageContentIfNeeded(conversationID: UUID, messageID: UUID, content: String) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        if conversations[conversationIndex].messages[messageIndex].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversations[conversationIndex].messages[messageIndex].content = content
        }
    }

    private func removeMessageIfEmpty(conversationID: UUID, messageID: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let content = conversations[conversationIndex].messages[messageIndex].content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if content.isEmpty {
            conversations[conversationIndex].messages.remove(at: messageIndex)
        }
    }

    private func touchConversation(_ conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        conversations[index].updatedAt = Date()
        sortConversations()
    }

    private func sortConversations() {
        conversations.sort(by: { $0.updatedAt > $1.updatedAt })
    }

    private func makeRequestMessages(for conversationID: UUID, excluding excludedMessageID: UUID) -> [APIChatMessage] {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return []
        }

        var requestMessages: [APIChatMessage] = []
        if let assistantKnowledgeContextText, !assistantKnowledgeContextText.isEmpty {
            requestMessages.append(
                APIChatMessage(
                    role: "system",
                    content: text("prompt.system.memoryKB", assistantKnowledgeContextText)
                )
            )
        }

        requestMessages += conversation.messages
            .filter { $0.id != excludedMessageID }
            .map {
                APIChatMessage(
                    role: $0.role.rawValue,
                    content: $0.content
                )
            }
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return requestMessages
    }

    private func updateTask(
        id: UUID,
        status: AgentTaskStatus,
        linkedConversationID: UUID?,
        lastError: String?
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        tasks[index].status = status
        tasks[index].linkedConversationID = linkedConversationID
        tasks[index].lastError = lastError
        tasks[index].updatedAt = Date()
        tasks.sort(by: { $0.updatedAt > $1.updatedAt })
    }

    private func addAgentLog(level: AgentLogLevel, title: String, detail: String) {
        agentLogs.append(
            AgentLogEntry(
                level: level,
                title: title,
                detail: detail
            )
        )
    }

    private func appendAgentRunToConversation(
        goal: String,
        summary: String,
        workspacePath: String,
        validationResult: LocalCommandResult?
    ) {
        let conversationID = createConversationAndSelect(
            title: Self.condensedTitle(from: goal, fallback: text("conversation.agentTaskFallback"))
        )

        appendMessage(
            ChatMessage(
                role: .user,
                content: text("conversation.agentGoal", goal, workspacePath)
            ),
            to: conversationID
        )

        var assistantText = text("conversation.agentDone", summary)
        if let validationResult {
            assistantText += text("conversation.validationExitCode", validationResult.exitCode)
            assistantText += Self.trimmedConversationLog(validationResult.combinedOutput(in: appLanguage))
        }

        appendMessage(
            ChatMessage(
                role: .assistant,
                content: assistantText
            ),
            to: conversationID
        )

        touchConversation(conversationID)
        persistSafely()
    }

    private static func trimmedConversationLog(_ text: String, maxCharacters: Int = 1800) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(maxCharacters)) + "\n... output truncated ..."
    }

    private var memoryPromptText: String? {
        guard !recentMemories.isEmpty else {
            return nil
        }

        return recentMemories.enumerated().map { index, memory in
            "\(index + 1). \(memory.content)"
        }.joined(separator: "\n")
    }

    private var knowledgeBasePromptText: String? {
        guard !recentKnowledgeBaseEntries.isEmpty else {
            return nil
        }

        return recentKnowledgeBaseEntries.enumerated().map { index, entry in
            let preview = String(entry.content.prefix(700))
            return """
            \(index + 1). \(entry.title)
            \(preview)
            """
        }.joined(separator: "\n\n")
    }

    private var assistantKnowledgeContextText: String? {
        var sections: [String] = []

        if let memoryPromptText, !memoryPromptText.isEmpty {
            sections.append(text("prompt.context.memory", memoryPromptText))
        }

        if let knowledgeBasePromptText, !knowledgeBasePromptText.isEmpty {
            sections.append(text("prompt.context.kb", knowledgeBasePromptText))
        }

        guard !sections.isEmpty else {
            return nil
        }

        return sections.joined(separator: "\n\n")
    }

    private func learnFromUserInput(_ text: String, source: String, force: Bool = false) {
        let trimmed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return
        }

        let keywords = [
            "记住", "以后", "默认", "需要", "不要", "必须", "请用",
            "优先", "保留", "继续", "喜欢", "习惯", "风格", "桌面", "工作区",
            "remember", "default", "prefer", "please use", "must", "keep", "continue",
            "workspace", "desktop", "style", "usually", "always",
            "ricorda", "predefinito", "preferisco", "usa", "deve", "mantieni",
            "continua", "workspace", "scrivania", "stile", "sempre"
        ]

        let shouldStore = force ||
            keywords.contains(where: { trimmed.contains($0) }) ||
            (trimmed.count <= 140 && source == "user_message")

        guard shouldStore else {
            return
        }

        storeMemory(String(trimmed.prefix(260)), source: source)
    }

    private func storeMemory(_ content: String, source: String) {
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }

        if let index = learnedMemories.firstIndex(where: {
            normalizedMemoryText($0.content) == normalizedMemoryText(cleaned) ||
            normalizedMemoryText($0.content).contains(normalizedMemoryText(cleaned)) ||
            normalizedMemoryText(cleaned).contains(normalizedMemoryText($0.content))
        }) {
            learnedMemories[index].content = cleaned
            learnedMemories[index].source = source
            learnedMemories[index].updatedAt = Date()
        } else {
            learnedMemories.insert(
                LearnedMemoryItem(
                    content: cleaned,
                    source: source
                ),
                at: 0
            )
        }

        if learnedMemories.count > 30 {
            learnedMemories = Array(learnedMemories.prefix(30))
        }

        persistSafely()
    }

    private func normalizedMemoryText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
    }

    func text(_ key: String) -> String {
        AppText.value(key, language: appLanguage)
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        AppText.value(key, language: appLanguage, arguments: arguments)
    }

    func relativeTimeString(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appLanguage.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func presentableErrorMessage(for error: Error) -> String {
        if let serviceError = error as? AIServiceError {
            return serviceError.localizedDescription(in: appLanguage)
        }

        if let workspaceError = error as? WorkspaceServiceError {
            return workspaceError.localizedDescription(in: appLanguage)
        }

        if let automationError = error as? AgentAutomationError {
            return automationError.localizedDescription(in: appLanguage)
        }

        return error.localizedDescription
    }

    private func persistSafely(reportErrors: Bool = false) {
        do {
            try persistenceStore.save(
                AppSnapshot(
                    configuration: configuration,
                    conversations: conversations,
                    tasks: tasks,
                    selectedConversationID: selectedConversationID,
                    workspacePath: workspacePath,
                    learnedMemories: learnedMemories,
                    knowledgeBaseEntries: knowledgeBaseEntries
                )
            )
        } catch {
            if reportErrors {
                errorMessage = text("error.localSaveFailed", error.localizedDescription)
            }
        }
    }
}
