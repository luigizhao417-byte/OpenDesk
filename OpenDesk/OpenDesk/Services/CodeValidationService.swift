import Foundation

struct CodeValidationResult {
    let validatorName: String
    let isValid: Bool
    let message: String
}

struct CodeValidationService {
    private let commandService: LocalCommandService
    private let fileManager = FileManager.default

    init(commandService: LocalCommandService = LocalCommandService()) {
        self.commandService = commandService
    }

    func validate(
        content: String,
        relativePath: String,
        workspaceURL: URL,
        language: AppLanguage
    ) async -> CodeValidationResult? {
        let ext = (relativePath as NSString).pathExtension.lowercased()

        let validator: (name: String, command: String)?
        switch ext {
        case "swift":
            validator = (localizedValidatorName("swift", language: language), "xcrun swiftc -typecheck '__FILE__'")
        case "json":
            validator = (localizedValidatorName("json", language: language), "plutil -lint '__FILE__'")
        case "plist":
            validator = (localizedValidatorName("plist", language: language), "plutil -lint '__FILE__'")
        case "sh", "bash", "zsh":
            validator = (localizedValidatorName("shell", language: language), "bash -n '__FILE__'")
        case "py":
            validator = (localizedValidatorName("python", language: language), "python3 -m py_compile '__FILE__'")
        default:
            validator = nil
        }

        guard let validator else {
            return nil
        }

        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("OpenDeskValidation", isDirectory: true)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let extensionSuffix = ext.isEmpty ? "" : ".\(ext)"
        let tempFileURL = tempDirectory.appendingPathComponent(UUID().uuidString + extensionSuffix)

        do {
            try content.write(to: tempFileURL, atomically: true, encoding: .utf8)
            let command = validator.command.replacingOccurrences(of: "__FILE__", with: tempFileURL.path)
            let result = try await commandService.run(command: command, in: workspaceURL, timeout: 60)
            try? fileManager.removeItem(at: tempFileURL)

            return CodeValidationResult(
                validatorName: validator.name,
                isValid: result.exitCode == 0,
                message: result.combinedOutput
            )
        } catch {
            try? fileManager.removeItem(at: tempFileURL)
            return CodeValidationResult(
                validatorName: validator.name,
                isValid: false,
                message: error.localizedDescription
            )
        }
    }

    private func localizedValidatorName(_ type: String, language: AppLanguage) -> String {
        switch (type, language) {
        case ("swift", .english):
            return "Swift syntax validation"
        case ("swift", .chinese):
            return "Swift 语法校验"
        case ("swift", .italian):
            return "validazione sintassi Swift"
        case ("json", .english):
            return "JSON validation"
        case ("json", .chinese):
            return "JSON 校验"
        case ("json", .italian):
            return "validazione JSON"
        case ("plist", .english):
            return "Plist validation"
        case ("plist", .chinese):
            return "Plist 校验"
        case ("plist", .italian):
            return "validazione Plist"
        case ("shell", .english):
            return "Shell syntax validation"
        case ("shell", .chinese):
            return "Shell 语法校验"
        case ("shell", .italian):
            return "validazione sintassi Shell"
        case ("python", .english):
            return "Python syntax validation"
        case ("python", .chinese):
            return "Python 语法校验"
        case ("python", .italian):
            return "validazione sintassi Python"
        default:
            return type
        }
    }
}
