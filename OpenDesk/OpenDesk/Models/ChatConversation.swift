import Foundation

struct ChatConversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var sourceTaskID: UUID?

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        sourceTaskID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.sourceTaskID = sourceTaskID
    }

    var previewText: String {
        guard let lastMessage = messages.last else {
            return "No messages yet"
        }

        let condensed = lastMessage.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if condensed.isEmpty {
            return "Preparing reply..."
        }

        return String(condensed.prefix(72))
    }

    func previewText(in language: AppLanguage) -> String {
        guard let lastMessage = messages.last else {
            return AppText.value("preview.empty", language: language)
        }

        let condensed = lastMessage.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if condensed.isEmpty {
            return AppText.value("preview.preparing", language: language)
        }

        return String(condensed.prefix(72))
    }
}
