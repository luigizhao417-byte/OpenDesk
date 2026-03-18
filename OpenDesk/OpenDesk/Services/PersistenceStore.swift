import Foundation

struct AppSnapshot: Codable {
    var configuration: APIConfiguration
    var conversations: [ChatConversation]
    var tasks: [AgentTask]
    var selectedConversationID: UUID?
    var workspacePath: String?
    var learnedMemories: [LearnedMemoryItem]?
    var knowledgeBaseEntries: [KnowledgeBaseEntry]?
}

final class PersistenceStore {
    static let shared = PersistenceStore()

    private let fileURL: URL
    private let legacyFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let appSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let folderURL = appSupportURL.appendingPathComponent("OpenDesk", isDirectory: true)
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        fileURL = folderURL.appendingPathComponent("AppState.json")
        legacyFileURL = appSupportURL
            .appendingPathComponent("AgentDesk", isDirectory: true)
            .appendingPathComponent("AppState.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> AppSnapshot {
        let candidateURL: URL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            candidateURL = fileURL
        } else if FileManager.default.fileExists(atPath: legacyFileURL.path) {
            candidateURL = legacyFileURL
        } else {
            return AppSnapshot(
                configuration: APIConfiguration(),
                conversations: [],
                tasks: [],
                selectedConversationID: nil,
                workspacePath: nil,
                learnedMemories: nil,
                knowledgeBaseEntries: nil
            )
        }

        guard let data = try? Data(contentsOf: candidateURL) else {
            return AppSnapshot(
                configuration: APIConfiguration(),
                conversations: [],
                tasks: [],
                selectedConversationID: nil,
                workspacePath: nil,
                learnedMemories: nil,
                knowledgeBaseEntries: nil
            )
        }

        do {
            return try decoder.decode(AppSnapshot.self, from: data)
        } catch {
            return AppSnapshot(
                configuration: APIConfiguration(),
                conversations: [],
                tasks: [],
                selectedConversationID: nil,
                workspacePath: nil,
                learnedMemories: nil,
                knowledgeBaseEntries: nil
            )
        }
    }

    func save(_ snapshot: AppSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
