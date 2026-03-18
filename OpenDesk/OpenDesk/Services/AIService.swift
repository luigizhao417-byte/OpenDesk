import Foundation

struct APIChatMessage: Encodable {
    let role: String
    let content: String
}

enum AIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The API URL is invalid. Please check the address in Settings."
        case .invalidResponse:
            return "The server returned data that could not be recognized."
        case let .requestFailed(statusCode, message):
            return "The request failed (\(statusCode)): \(message)"
        case .emptyResponse:
            return "The model did not return any content."
        }
    }

    func localizedDescription(in language: AppLanguage) -> String {
        switch self {
        case .invalidURL:
            return AppText.value("api.error.invalidURL", language: language)
        case .invalidResponse:
            return AppText.value("api.error.invalidResponse", language: language)
        case let .requestFailed(statusCode, message):
            return AppText.value("api.error.requestFailed", language: language, arguments: [statusCode, message])
        case .emptyResponse:
            return AppText.value("api.error.emptyResponse", language: language)
        }
    }
}

struct AIService {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func completeChat(
        configuration: APIConfiguration,
        messages: [APIChatMessage]
    ) async throws -> String {
        let endpoint = try normalizedEndpoint(from: configuration.apiURL)
        let requestBody = ChatCompletionRequest(
            model: configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: messages,
            stream: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AIServiceError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        let text = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            throw AIServiceError.emptyResponse
        }

        return text
    }

    func streamChat(
        configuration: APIConfiguration,
        messages: [APIChatMessage],
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        let endpoint = try normalizedEndpoint(from: configuration.apiURL)
        let requestBody = ChatCompletionRequest(
            model: configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: messages,
            stream: true
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorData = try await collectData(from: bytes)
            let message = parseErrorMessage(from: errorData) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AIServiceError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        var fullText = ""
        var sawStreamingEvent = false
        var nonStreamingLines: [String] = []

        for try await rawLine in bytes.lines {
            try Task.checkCancellation()

            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            if trimmedLine.hasPrefix("data:") {
                sawStreamingEvent = true
                let payload = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespaces)

                if payload == "[DONE]" {
                    break
                }

                guard let payloadData = payload.data(using: .utf8) else {
                    continue
                }

                if let chunk = try? decoder.decode(StreamChunk.self, from: payloadData) {
                    if let piece = chunk.choices.first?.delta?.content, !piece.isEmpty {
                        fullText += piece
                        await onDelta(piece)
                    } else if let fallback = chunk.choices.first?.message?.content, !fallback.isEmpty {
                        fullText += fallback
                        await onDelta(fallback)
                    }
                }
            } else if !sawStreamingEvent {
                nonStreamingLines.append(rawLine)
            }
        }

        if sawStreamingEvent {
            if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AIServiceError.emptyResponse
            }

            return fullText
        }

        let plainBody = nonStreamingLines.joined(separator: "\n")
        guard let bodyData = plainBody.data(using: .utf8) else {
            throw AIServiceError.invalidResponse
        }

        if let errorMessage = parseErrorMessage(from: bodyData) {
            throw AIServiceError.requestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let completion = try decoder.decode(ChatCompletionResponse.self, from: bodyData)
        let text = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            throw AIServiceError.emptyResponse
        }

        await onDelta(text)
        return text
    }

    private func normalizedEndpoint(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil, components.host != nil else {
            throw AIServiceError.invalidURL
        }

        let host = components.host?.lowercased() ?? ""
        let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)

        if path.isEmpty || path == "/" {
            components.path = host.contains("deepseek") ? "/chat/completions" : "/v1/chat/completions"
        } else if path == "/v1" || path == "/v1/" {
            components.path = "/v1/chat/completions"
        } else if path.hasSuffix("/") {
            components.path = String(path.dropLast())
        }

        guard let url = components.url else {
            throw AIServiceError.invalidURL
        }

        return url
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }

        return nil
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIChatMessage]
    let stream: Bool
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        struct Message: Decodable {
            let content: String?
        }

        let delta: Delta?
        let message: Message?
    }

    let choices: [Choice]
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct APIErrorDetail: Decodable {
        let message: String?
    }

    let error: APIErrorDetail?
}
