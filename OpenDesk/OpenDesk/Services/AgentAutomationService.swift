import Foundation

struct AgentRunSummary {
    let message: String
    let wroteFiles: Bool
    let validationResult: LocalCommandResult?
}

enum AgentAutomationError: LocalizedError {
    case invalidPlan(String)
    case exhaustedIterations

    var errorDescription: String? {
        switch self {
        case let .invalidPlan(message):
            return "The agent plan format is invalid: \(message)"
        case .exhaustedIterations:
            return "The agent reached the maximum number of execution rounds and the task may still be incomplete."
        }
    }

    func localizedDescription(in language: AppLanguage) -> String {
        switch self {
        case let .invalidPlan(message):
            return AppText.value("agent.error.invalidPlan", language: language, arguments: [message])
        case .exhaustedIterations:
            return AppText.value("agent.error.exhaustedIterations", language: language)
        }
    }
}

struct AgentAutomationService {
    private let aiService: AIService
    private let workspaceService: WorkspaceService
    private let commandService: LocalCommandService
    private let projectValidator: ProjectValidator
    private let codeValidationService: CodeValidationService

    init(
        aiService: AIService = AIService(),
        workspaceService: WorkspaceService = WorkspaceService(),
        commandService: LocalCommandService = LocalCommandService(),
        projectValidator: ProjectValidator = ProjectValidator(),
        codeValidationService: CodeValidationService = CodeValidationService()
    ) {
        self.aiService = aiService
        self.workspaceService = workspaceService
        self.commandService = commandService
        self.projectValidator = projectValidator
        self.codeValidationService = codeValidationService
    }

    func run(
        goal: String,
        workspaceURL: URL,
        configuration: APIConfiguration,
        memoryContext: String?,
        language: AppLanguage,
        onLog: @escaping @Sendable (AgentLogEntry) async -> Void,
        onLearnedMemory: @escaping @Sendable (String) async -> Void
    ) async throws -> AgentRunSummary {
        let snapshot = try workspaceService.snapshot(in: workspaceURL, lineBudget: 5000, fileLimit: 40)
        await onLog(
            AgentLogEntry(
                level: .info,
                title: localized(language, zh: "已载入上下文", en: "Context Loaded", it: "Contesto Caricato"),
                detail: localized(
                    language,
                    zh: "工作区共读取 \(snapshot.fileList.count) 个文件路径，代码上下文约 \(snapshot.includedLineCount) 行。",
                    en: "Read \(snapshot.fileList.count) file paths from the workspace, with about \(snapshot.includedLineCount) lines of code context.",
                    it: "Sono stati letti \(snapshot.fileList.count) percorsi file dal workspace, con circa \(snapshot.includedLineCount) righe di contesto codice."
                )
            )
        )

        var messages = [APIChatMessage(role: "system", content: Self.systemPrompt(in: language))]
        if let memoryContext, !memoryContext.isEmpty {
            messages.append(
                APIChatMessage(
                    role: "system",
                    content: localized(
                        language,
                        zh: "以下是智能体从用户历史输入中学习到的长期偏好与约束，请尽量持续遵守：\n\(memoryContext)",
                        en: "The following long-term preferences and constraints were learned from the user's previous inputs. Please keep following them when possible:\n\(memoryContext)",
                        it: "Le seguenti preferenze e vincoli di lungo periodo sono stati appresi dagli input precedenti dell'utente. Cerca di seguirli in modo coerente:\n\(memoryContext)"
                    )
                )
            )
        }
        messages.append(APIChatMessage(role: "user", content: Self.initialPrompt(goal: goal, snapshot: snapshot, language: language)))

        var wroteFiles = false
        var finalSummary = localized(language, zh: "智能体任务已执行。", en: "The agent task has been executed.", it: "L'attivita dell'agente e stata eseguita.")
        var reachedFinish = false

        for round in 1 ... 6 {
            let roundResult = try await executeRound(
                label: localized(language, zh: "第\(round)轮", en: "Round \(round)", it: "Round \(round)"),
                workspaceURL: workspaceURL,
                configuration: configuration,
                language: language,
                messages: &messages,
                onLog: onLog,
                onLearnedMemory: onLearnedMemory
            )

            wroteFiles = wroteFiles || roundResult.wroteFiles

            if let finishReason = roundResult.finishReason {
                finalSummary = finishReason
                reachedFinish = true
                break
            }
        }

        var validationResult: LocalCommandResult?

        if wroteFiles, let validationCommand = projectValidator.suggestedCommand(in: workspaceURL, language: language) {
            validationResult = try await validate(
                using: validationCommand,
                workspaceURL: workspaceURL,
                language: language,
                onLog: onLog
            )

            if let currentValidationResult = validationResult, currentValidationResult.exitCode != 0 {
                for repairRound in 1 ... 2 {
                    messages.append(
                        APIChatMessage(
                            role: "user",
                            content: localized(
                                language,
                                zh: """
                                自动自检失败。请根据下面的错误继续修复当前工作区，然后返回下一轮 JSON 动作。
                                你可以继续 read_file / write_file / run_command。
                                只有当你认为可以再次检查时，才返回 finish。

                                \(currentValidationResult.combinedOutput(in: language))
                                """,
                                en: """
                                Automatic validation failed. Please continue fixing the current workspace based on the errors below, then return the next JSON actions.
                                You can continue using read_file / write_file / run_command.
                                Only return finish when you believe the project is ready to be validated again.

                                \(currentValidationResult.combinedOutput(in: language))
                                """,
                                it: """
                                La validazione automatica e fallita. Continua a correggere il workspace corrente in base agli errori qui sotto, poi restituisci le prossime azioni JSON.
                                Puoi continuare a usare read_file / write_file / run_command.
                                Restituisci finish solo quando ritieni che il progetto sia pronto per una nuova validazione.

                                \(currentValidationResult.combinedOutput(in: language))
                                """
                            )
                        )
                    )

                    let repairResult = try await executeRound(
                        label: localized(language, zh: "修复轮\(repairRound)", en: "Repair Round \(repairRound)", it: "Round di Correzione \(repairRound)"),
                        workspaceURL: workspaceURL,
                        configuration: configuration,
                        language: language,
                        messages: &messages,
                        onLog: onLog,
                        onLearnedMemory: onLearnedMemory
                    )

                    wroteFiles = wroteFiles || repairResult.wroteFiles

                    validationResult = try await validate(
                        using: validationCommand,
                        workspaceURL: workspaceURL,
                        language: language,
                        onLog: onLog
                    )

                    if let finishReason = repairResult.finishReason {
                        finalSummary = finishReason
                    }

                    if validationResult?.exitCode == 0 {
                        reachedFinish = true
                        break
                    }
                }
            }
        } else if wroteFiles {
            await onLog(
                AgentLogEntry(
                    level: .warning,
                    title: localized(language, zh: "未发现自检命令", en: "No Validation Command Found", it: "Nessun Comando di Validazione Trovato"),
                    detail: localized(
                        language,
                        zh: "当前工作区没有识别到 `.xcodeproj` 或 `Package.swift`，因此无法自动编译检查。",
                        en: "No `.xcodeproj` or `Package.swift` was detected in the current workspace, so automatic build validation cannot run.",
                        it: "Nel workspace corrente non e stato rilevato alcun `.xcodeproj` o `Package.swift`, quindi la validazione automatica della build non puo essere eseguita."
                    )
                )
            )
        }

        if !reachedFinish && !wroteFiles {
            throw AgentAutomationError.exhaustedIterations
        }

        return AgentRunSummary(
            message: finalSummary,
            wroteFiles: wroteFiles,
            validationResult: validationResult
        )
    }

    private func executeRound(
        label: String,
        workspaceURL: URL,
        configuration: APIConfiguration,
        language: AppLanguage,
        messages: inout [APIChatMessage],
        onLog: @escaping @Sendable (AgentLogEntry) async -> Void,
        onLearnedMemory: @escaping @Sendable (String) async -> Void
    ) async throws -> RoundResult {
        let responseText = try await aiService.completeChat(
            configuration: configuration,
            messages: messages
        )

        let roundPlan = try decodeRoundPlan(from: responseText, language: language)

        await onLog(
            AgentLogEntry(
                level: .info,
                title: label,
                detail: roundPlan.summary.isEmpty
                    ? localized(language, zh: "模型已返回一组动作。", en: "The model returned a set of actions.", it: "Il modello ha restituito una serie di azioni.")
                    : roundPlan.summary
            )
        )

        guard !roundPlan.actions.isEmpty else {
            throw AgentAutomationError.invalidPlan(localized(language, zh: "actions 为空。", en: "actions is empty.", it: "actions e vuoto."))
        }

        var toolOutputs: [String] = []
        var finishReason: String?
        var wroteFiles = false

        for action in roundPlan.actions.prefix(6) {
            let output = try await perform(
                action: action,
                workspaceURL: workspaceURL,
                language: language,
                onLog: onLog,
                onLearnedMemory: onLearnedMemory
            )
            toolOutputs.append(output)

            let normalizedType = action.type.lowercased()
            if normalizedType == "write_file" || normalizedType == "append_file" || normalizedType == "create_folder" {
                wroteFiles = true
            }

            if normalizedType == "finish" {
                finishReason = action.reason ?? roundPlan.summary
                break
            }
        }

        messages.append(
            APIChatMessage(
                role: "assistant",
                content: localized(
                    language,
                    zh: "\(label) 已规划并执行 \(min(roundPlan.actions.count, 6)) 个动作。",
                    en: "\(label) planned and executed \(min(roundPlan.actions.count, 6)) actions.",
                    it: "\(label) ha pianificato ed eseguito \(min(roundPlan.actions.count, 6)) azioni."
                )
            )
        )

        if finishReason == nil {
            messages.append(
                APIChatMessage(
                    role: "user",
                    content: localized(
                        language,
                        zh: """
                        工具执行结果如下：
                        \(toolOutputs.joined(separator: "\n\n"))

                        如果任务已经完成，请返回 finish。
                        如果还没完成，请继续返回下一轮 JSON。
                        """,
                        en: """
                        Tool execution results:
                        \(toolOutputs.joined(separator: "\n\n"))

                        If the task is already complete, return finish.
                        If it is not complete yet, continue with the next JSON round.
                        """,
                        it: """
                        Risultati dell'esecuzione degli strumenti:
                        \(toolOutputs.joined(separator: "\n\n"))

                        Se l'attivita e gia completata, restituisci finish.
                        Se non e ancora completa, continua con il prossimo round JSON.
                        """
                    )
                )
            )
        }

        return RoundResult(
            wroteFiles: wroteFiles,
            finishReason: finishReason
        )
    }

    private func perform(
        action: AgentAction,
        workspaceURL: URL,
        language: AppLanguage,
        onLog: @escaping @Sendable (AgentLogEntry) async -> Void,
        onLearnedMemory: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        switch action.type.lowercased() {
        case "create_folder":
            guard let path = action.path else {
                throw AgentAutomationError.invalidPlan(localized(language, zh: "create_folder 缺少 path。", en: "create_folder is missing path.", it: "create_folder non contiene path."))
            }

            try workspaceService.createFolder(at: path, in: workspaceURL)
            await onLog(
                AgentLogEntry(
                    level: .success,
                    title: localized(language, zh: "创建文件夹", en: "Create Folder", it: "Crea Cartella"),
                    detail: path
                )
            )
            return "create_folder \(path): success"

        case "write_file":
            guard let path = action.path, let content = action.content else {
                throw AgentAutomationError.invalidPlan(localized(language, zh: "write_file 缺少 path 或 content。", en: "write_file is missing path or content.", it: "write_file non contiene path o content."))
            }

            if let validationResult = await codeValidationService.validate(
                content: content,
                relativePath: path,
                workspaceURL: workspaceURL,
                language: language
            ) {
                await onLog(
                    AgentLogEntry(
                        level: validationResult.isValid ? .info : .warning,
                        title: localized(language, zh: "写入前预校验", en: "Pre-write Validation", it: "Validazione Prima della Scrittura"),
                        detail: "\(path)\n\(validationResult.validatorName)\n\(validationResult.message)"
                    )
                )

                guard validationResult.isValid else {
                    return "write_file \(path): validation_failed\n\(validationResult.message)"
                }
            }

            try workspaceService.writeFile(at: path, content: content, in: workspaceURL)
            await onLog(
                AgentLogEntry(
                    level: .success,
                    title: localized(language, zh: "写入文件", en: "Write File", it: "Scrivi File"),
                    detail: "\(path)\n\(summarizeContent(content, language: language))"
                )
            )
            return "write_file \(path): wrote \(content.count) chars"

        case "append_file":
            guard let path = action.path, let content = action.content else {
                throw AgentAutomationError.invalidPlan(localized(language, zh: "append_file 缺少 path 或 content。", en: "append_file is missing path or content.", it: "append_file non contiene path o content."))
            }

            let existingContent = (try? workspaceService.rawFileContents(at: path, in: workspaceURL)) ?? ""
            let separator = existingContent.isEmpty || existingContent.hasSuffix("\n") ? "" : "\n"
            let mergedContent = existingContent + separator + content

            if let validationResult = await codeValidationService.validate(
                content: mergedContent,
                relativePath: path,
                workspaceURL: workspaceURL,
                language: language
            ) {
                await onLog(
                    AgentLogEntry(
                        level: validationResult.isValid ? .info : .warning,
                        title: localized(language, zh: "追加前预校验", en: "Pre-append Validation", it: "Validazione Prima dell'Aggiunta"),
                        detail: "\(path)\n\(validationResult.validatorName)\n\(validationResult.message)"
                    )
                )

                guard validationResult.isValid else {
                    return "append_file \(path): validation_failed\n\(validationResult.message)"
                }
            }

            try workspaceService.appendFile(at: path, content: content, in: workspaceURL)
            await onLog(
                AgentLogEntry(
                    level: .success,
                    title: localized(language, zh: "追加文件", en: "Append File", it: "Aggiungi al File"),
                    detail: "\(path)\n\(summarizeContent(content, language: language))"
                )
            )
            return "append_file \(path): appended \(content.count) chars"

        case "read_file":
            guard let path = action.path else {
                throw AgentAutomationError.invalidPlan(localized(language, zh: "read_file 缺少 path。", en: "read_file is missing path.", it: "read_file non contiene path."))
            }

            let content = try workspaceService.readFile(at: path, in: workspaceURL)
            await onLog(
                AgentLogEntry(
                    level: .info,
                    title: localized(language, zh: "读取文件", en: "Read File", it: "Leggi File"),
                    detail: path
                )
            )
            return "read_file \(path):\n\(content)"

        case "run_command":
            guard let command = action.command else {
                throw AgentAutomationError.invalidPlan(localized(language, zh: "run_command 缺少 command。", en: "run_command is missing command.", it: "run_command non contiene command."))
            }

            let result = try await commandService.run(command: command, in: workspaceURL)
            await onLog(
                AgentLogEntry(
                    level: result.exitCode == 0 ? .success : .warning,
                    title: localized(language, zh: "运行命令", en: "Run Command", it: "Esegui Comando"),
                    detail: "\(command)\n\n\(result.combinedOutput(in: language))"
                )
            )
            return "run_command \(command): exit \(result.exitCode)\n\(result.combinedOutput(in: language))"

        case "remember":
            guard let content = action.content else {
                throw AgentAutomationError.invalidPlan(localized(language, zh: "remember 缺少 content。", en: "remember is missing content.", it: "remember non contiene content."))
            }

            await onLearnedMemory(content)
            await onLog(
                AgentLogEntry(
                    level: .info,
                    title: localized(language, zh: "更新长期记忆", en: "Update Long-Term Memory", it: "Aggiorna Memoria a Lungo Termine"),
                    detail: content
                )
            )
            return "remember: saved"

        case "finish":
            let reason = action.reason ?? localized(language, zh: "任务已完成。", en: "The task is complete.", it: "L'attivita e completata.")
            await onLog(
                AgentLogEntry(
                    level: .success,
                    title: localized(language, zh: "模型判断完成", en: "Model Marked Complete", it: "Il Modello ha Segnato il Completamento"),
                    detail: reason
                )
            )
            return "finish: \(reason)"

        default:
            throw AgentAutomationError.invalidPlan(localized(language, zh: "不支持的 action 类型：\(action.type)", en: "Unsupported action type: \(action.type)", it: "Tipo di action non supportato: \(action.type)"))
        }
    }

    private func validate(
        using validationCommand: ProjectValidationCommand,
        workspaceURL: URL,
        language: AppLanguage,
        onLog: @escaping @Sendable (AgentLogEntry) async -> Void
    ) async throws -> LocalCommandResult {
        await onLog(
            AgentLogEntry(
                level: .info,
                title: localized(language, zh: "开始自检", en: "Start Validation", it: "Avvia Validazione"),
                detail: validationCommand.command
            )
        )

        let result = try await commandService.run(
            command: validationCommand.command,
            in: workspaceURL
        )

        await onLog(
            AgentLogEntry(
                level: result.exitCode == 0 ? .success : .warning,
                title: validationCommand.title,
                detail: result.combinedOutput(in: language)
            )
        )

        return result
    }

    private func extractJSON(from rawText: String) -> String {
        if let start = rawText.range(of: "```"),
           let end = rawText.range(of: "```", options: .backwards),
           start.lowerBound != end.lowerBound {
            let fenced = String(rawText[start.upperBound ..< end.lowerBound])
            if let jsonStart = fenced.firstIndex(of: "{"), let jsonEnd = fenced.lastIndex(of: "}") {
                return String(fenced[jsonStart ... jsonEnd])
            }
        }

        if let jsonStart = rawText.firstIndex(of: "{"), let jsonEnd = rawText.lastIndex(of: "}") {
            return String(rawText[jsonStart ... jsonEnd])
        }

        return rawText
    }

    private func decodeRoundPlan(from rawText: String, language: AppLanguage) throws -> RoundPlan {
        let jsonText = extractJSON(from: rawText)
        guard let data = jsonText.data(using: .utf8) else {
            throw AgentAutomationError.invalidPlan(localized(language, zh: "无法解析 JSON 文本。", en: "Unable to parse the JSON text.", it: "Impossibile analizzare il testo JSON."))
        }

        do {
            return try JSONDecoder().decode(RoundPlan.self, from: data)
        } catch {
            throw AgentAutomationError.invalidPlan(
                localized(
                    language,
                    zh: "JSON 解码失败：\(error.localizedDescription)\n原始返回：\(rawText)",
                    en: "JSON decoding failed: \(error.localizedDescription)\nRaw response: \(rawText)",
                    it: "Decodifica JSON non riuscita: \(error.localizedDescription)\nRisposta grezza: \(rawText)"
                )
            )
        }
    }

    private func summarizeContent(_ content: String, language: AppLanguage) -> String {
        let lineCount = content.components(separatedBy: .newlines).count
        let preview = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(180)

        return localized(
            language,
            zh: "共 \(lineCount) 行，预览：\(preview)",
            en: "\(lineCount) lines total, preview: \(preview)",
            it: "\(lineCount) righe totali, anteprima: \(preview)"
        )
    }

    private static func initialPrompt(goal: String, snapshot: WorkspaceSnapshot, language: AppLanguage) -> String {
        switch language {
        case .english:
            return """
            Goal:
            \(goal)

            Current workspace snapshot:
            \(snapshot.promptText(in: language))

            Extra requirements:
            1. You are working inside a real local workspace, so paths must be relative.
            2. If you need to understand existing code, use read_file first.
            3. When writing a file, always provide the full file contents.
            4. If the workspace is empty, you may create folders and project files directly.
            5. After you return finish, the app will run one local validation pass automatically. If validation fails, you will receive the error output and continue fixing it.
            6. If the user runs the same workspace again later, continue iterating on top of the existing code.

            Now return round 1 JSON.
            """
        case .chinese:
            return """
            目标：
            \(goal)

            当前工作区快照：
            \(snapshot.promptText(in: language))

            额外要求：
            1. 你在一个真实的本地工作区内工作，路径必须使用相对路径。
            2. 如需理解现有代码，先用 read_file。
            3. 写文件时必须给出完整文件内容。
            4. 如果当前工作区为空，你可以直接创建文件夹和项目文件。
            5. 当前应用会在你 finish 后自动做一次本地自检；如果自检失败，你还会收到错误输出继续修复。
            6. 如果用户之后再次运行同一个工作区，你需要基于原代码继续迭代。

            现在返回第 1 轮 JSON。
            """
        case .italian:
            return """
            Obiettivo:
            \(goal)

            Snapshot attuale del workspace:
            \(snapshot.promptText(in: language))

            Requisiti aggiuntivi:
            1. Stai lavorando in un vero workspace locale, quindi i percorsi devono essere relativi.
            2. Se devi comprendere il codice esistente, usa prima read_file.
            3. Quando scrivi un file, devi sempre fornire il contenuto completo del file.
            4. Se il workspace e vuoto, puoi creare direttamente cartelle e file di progetto.
            5. Dopo finish, l'app eseguira automaticamente una validazione locale. Se la validazione fallisce, riceverai l'output degli errori e continuerai a correggere.
            6. Se l'utente esegue di nuovo lo stesso workspace in seguito, devi continuare a iterare sul codice esistente.

            Ora restituisci il JSON del round 1.
            """
        }
    }

    private static func systemPrompt(in language: AppLanguage) -> String {
        switch language {
        case .english:
            return """
            You are a macOS local coding agent. You may operate on the workspace only through JSON actions.
            You must return exactly one JSON object. Do not use Markdown and do not add extra explanation.

            Allowed schema:
            {
              "summary": "Summary of this round",
              "actions": [
                { "type": "read_file", "path": "Sources/App.swift", "reason": "Read the existing implementation" },
                { "type": "create_folder", "path": "Game/Assets", "reason": "Create the asset directory" },
                { "type": "write_file", "path": "Game/Main.swift", "content": "full file contents", "reason": "Write the main program" },
                { "type": "append_file", "path": "README.md", "content": "content to append", "reason": "Add more documentation" },
                { "type": "remember", "content": "The user prefers continuing in the desktop workspace", "reason": "Save a long-term preference" },
                { "type": "run_command", "command": "swift build", "reason": "Proactively check the project" },
                { "type": "finish", "reason": "The task is complete and ready for automatic validation" }
              ]
            }

            Rules:
            - path must be relative to the workspace and must not be absolute.
            - Return at most 6 actions per round.
            - You may generate many text file types, such as swift/json/md/html/css/js/ts/py/sh/yaml/toml/plist/txt/csv/xml/svg/sql.
            - Prefer editing existing code over rewriting the whole project.
            - Do not output dangerous commands such as sudo, rm -rf, or git reset --hard.
            - If you need more code context, use read_file.
            - When you discover user preferences, project constraints, or directory rules worth keeping long term, you may use remember.
            - Return finish only when the project is ready for automatic validation.
            """
        case .chinese:
            return """
            你是一个 macOS 本地编码智能体。你只能通过 JSON 动作操作工作区。
            你必须只返回一个 JSON 对象，不要使用 Markdown，不要添加解释文字。

            允许的 schema：
            {
              "summary": "本轮计划概述",
              "actions": [
                { "type": "read_file", "path": "Sources/App.swift", "reason": "读取现有实现" },
                { "type": "create_folder", "path": "Game/Assets", "reason": "创建资源目录" },
                { "type": "write_file", "path": "Game/Main.swift", "content": "完整文件内容", "reason": "写入主程序" },
                { "type": "append_file", "path": "README.md", "content": "追加内容", "reason": "补充说明" },
                { "type": "remember", "content": "用户偏好使用桌面工作区继续迭代", "reason": "保存长期偏好" },
                { "type": "run_command", "command": "swift build", "reason": "主动检查" },
                { "type": "finish", "reason": "任务已完成，可以进入自动自检" }
              ]
            }

            规则：
            - path 必须是相对工作区路径，不能是绝对路径。
            - 一轮最多返回 6 个 actions。
            - 你可以生成多种文本文件，例如 swift/json/md/html/css/js/ts/py/sh/yaml/toml/plist/txt/csv/xml/svg/sql。
            - 优先修改现有代码，而不是重写整个项目。
            - 不要输出危险命令，例如 sudo、rm -rf、git reset --hard。
            - 如果需要更多代码上下文，使用 read_file。
            - 当你发现适合长期记住的用户偏好、项目约束或目录规则时，可以使用 remember。
            - 只有当你认为已经可以交给自动自检时，才返回 finish。
            """
        case .italian:
            return """
            Sei un agente locale di coding per macOS. Puoi operare sul workspace solo tramite azioni JSON.
            Devi restituire esattamente un oggetto JSON. Non usare Markdown e non aggiungere testo esplicativo extra.

            Schema consentito:
            {
              "summary": "Riepilogo di questo round",
              "actions": [
                { "type": "read_file", "path": "Sources/App.swift", "reason": "Leggere l'implementazione esistente" },
                { "type": "create_folder", "path": "Game/Assets", "reason": "Creare la cartella delle risorse" },
                { "type": "write_file", "path": "Game/Main.swift", "content": "contenuto completo del file", "reason": "Scrivere il programma principale" },
                { "type": "append_file", "path": "README.md", "content": "contenuto da aggiungere", "reason": "Aggiungere documentazione" },
                { "type": "remember", "content": "L'utente preferisce continuare nel workspace desktop", "reason": "Salvare una preferenza a lungo termine" },
                { "type": "run_command", "command": "swift build", "reason": "Controllare proattivamente il progetto" },
                { "type": "finish", "reason": "L'attivita e completa ed e pronta per la validazione automatica" }
              ]
            }

            Regole:
            - path deve essere relativo al workspace e non puo essere assoluto.
            - Restituisci al massimo 6 azioni per round.
            - Puoi generare molti tipi di file di testo, come swift/json/md/html/css/js/ts/py/sh/yaml/toml/plist/txt/csv/xml/svg/sql.
            - Preferisci modificare il codice esistente invece di riscrivere l'intero progetto.
            - Non generare comandi pericolosi come sudo, rm -rf o git reset --hard.
            - Se hai bisogno di piu contesto sul codice, usa read_file.
            - Quando scopri preferenze utente, vincoli di progetto o regole di directory utili nel lungo periodo, puoi usare remember.
            - Restituisci finish solo quando il progetto e pronto per la validazione automatica.
            """
        }
    }

    private func localized(_ language: AppLanguage, zh: String, en: String, it: String) -> String {
        switch language {
        case .english:
            return en
        case .chinese:
            return zh
        case .italian:
            return it
        }
    }
}

private struct RoundPlan: Decodable {
    let summary: String
    let actions: [AgentAction]
}

private struct AgentAction: Decodable {
    let type: String
    let path: String?
    let content: String?
    let command: String?
    let reason: String?
}

private struct RoundResult {
    let wroteFiles: Bool
    let finishReason: String?
}
