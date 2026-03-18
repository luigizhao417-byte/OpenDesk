import Foundation

enum AgentTaskStatus: String, Codable, CaseIterable {
    case pending
    case running
    case completed

    var title: String {
        switch self {
        case .pending:
            return "Pending"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        }
    }

    func localizedTitle(in language: AppLanguage) -> String {
        switch self {
        case .pending:
            return AppText.value("task.status.pending", language: language)
        case .running:
            return AppText.value("task.status.running", language: language)
        case .completed:
            return AppText.value("task.status.completed", language: language)
        }
    }
}

struct AgentTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var status: AgentTaskStatus
    var createdAt: Date
    var updatedAt: Date
    var linkedConversationID: UUID?
    var lastError: String?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        status: AgentTaskStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        linkedConversationID: UUID? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linkedConversationID = linkedConversationID
        self.lastError = lastError
    }
}
