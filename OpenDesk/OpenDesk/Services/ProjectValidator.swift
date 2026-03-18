import Foundation

struct ProjectValidationCommand {
    let title: String
    let command: String
}

struct ProjectValidator {
    private let fileManager = FileManager.default

    func suggestedCommand(in root: URL, language: AppLanguage) -> ProjectValidationCommand? {
        if let xcodeProjectURL = findProjectDirectory(in: root, extension: "xcodeproj", maxDepth: 2) {
            let projectName = xcodeProjectURL.deletingPathExtension().lastPathComponent
            let relativePath = relativePath(from: root, to: xcodeProjectURL)
            return ProjectValidationCommand(
                title: localizedXcodebuildTitle(for: language),
                command: "xcodebuild -project '\(relativePath)' -scheme '\(projectName)' -configuration Debug -destination 'platform=macOS' build"
            )
        }

        if fileManager.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return ProjectValidationCommand(
                title: localizedSwiftBuildTitle(for: language),
                command: "swift build"
            )
        }

        return nil
    }

    private func findProjectDirectory(in root: URL, extension pathExtension: String, maxDepth: Int) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            return nil
        }

        let rootDepth = root.standardizedFileURL.pathComponents.count

        for case let itemURL as URL in enumerator {
            let depth = itemURL.standardizedFileURL.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if itemURL.pathExtension.lowercased() == pathExtension.lowercased() {
                return itemURL
            }
        }

        return nil
    }

    private func relativePath(from root: URL, to target: URL) -> String {
        target.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    private func localizedXcodebuildTitle(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "xcodebuild validation"
        case .chinese:
            return "xcodebuild 自检"
        case .italian:
            return "validazione xcodebuild"
        }
    }

    private func localizedSwiftBuildTitle(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return "swift build validation"
        case .chinese:
            return "swift build 自检"
        case .italian:
            return "validazione swift build"
        }
    }
}
