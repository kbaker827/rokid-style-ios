import Foundation

// ── Unified AI completion client ──────────────────────────────────────────────────────────────
// Supports OpenAI, Anthropic, Google Gemini, xAI Grok.
// Uses URLSession async/await — no third-party dependencies.

enum AiApiError: LocalizedError {
    case missingAPIKey(String)
    case httpError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): return "No API key set for \(p). Open Settings to add your key."
        case .httpError(let code, let msg): return "API error \(code): \(msg)"
        case .decodingError(let msg): return "Unexpected response: \(msg)"
        }
    }
}

struct AiApiClient {

    static func complete(
        model:        AiModel,
        apiKey:       String,
        messages:     [ChatMessage],
        systemPrompt: String?
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AiApiError.missingAPIKey(model.provider.displayName)
        }
        switch model.provider {
        case .openAI, .grok:
            return try await openAiComplete(model: model, apiKey: apiKey,
                                            messages: messages, system: systemPrompt)
        case .anthropic:
            return try await anthropicComplete(model: model, apiKey: apiKey,
                                               messages: messages, system: systemPrompt)
        case .gemini:
            return try await geminiComplete(model: model, apiKey: apiKey,
                                            messages: messages, system: systemPrompt)
        }
    }

    // ── OpenAI / Grok ─────────────────────────────────────────────────────────────────────────

    private static func openAiComplete(model: AiModel, apiKey: String,
                                       messages: [ChatMessage], system: String?) async throws -> String {
        var msgs = [ChatMessage]()
        if let s = system, !s.isEmpty { msgs.append(.init(role: "system", content: s)) }
        msgs.append(contentsOf: messages)

        let body: [String: Any] = [
            "model":      model.id,
            "messages":   msgs.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": 512
        ]
        let data = try await post(
            url:     "\(model.provider.baseURL)/chat/completions",
            body:    body,
            headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"]
        )
        guard let choices = data["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AiApiError.decodingError("choices[0].message.content missing")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── Anthropic ─────────────────────────────────────────────────────────────────────────────

    private static func anthropicComplete(model: AiModel, apiKey: String,
                                          messages: [ChatMessage], system: String?) async throws -> String {
        var body: [String: Any] = [
            "model":      model.id,
            "max_tokens": 512,
            "messages":   messages.map { ["role": $0.role, "content": $0.content] }
        ]
        if let s = system, !s.isEmpty { body["system"] = s }

        let data = try await post(
            url:     "https://api.anthropic.com/v1/messages",
            body:    body,
            headers: [
                "x-api-key":         apiKey,
                "anthropic-version": "2023-06-01",
                "Content-Type":      "application/json"
            ]
        )
        guard let content = data["content"] as? [[String: Any]],
              let text    = content.first?["text"] as? String else {
            throw AiApiError.decodingError("content[0].text missing")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── Google Gemini ─────────────────────────────────────────────────────────────────────────

    private static func geminiComplete(model: AiModel, apiKey: String,
                                       messages: [ChatMessage], system: String?) async throws -> String {
        var contents = [[String: Any]]()

        if let s = system, !s.isEmpty {
            contents.append(["role": "user",  "parts": [["text": "Instructions: \(s)"]]])
            contents.append(["role": "model", "parts": [["text": "Understood."]]])
        }
        for m in messages {
            let role = m.role == "assistant" ? "model" : "user"
            contents.append(["role": role, "parts": [["text": m.content]]])
        }

        let body: [String: Any] = ["contents": contents]
        let url = "https://generativelanguage.googleapis.com/v1beta/models/\(model.id):generateContent?key=\(apiKey)"

        let data = try await post(url: url, body: body, headers: ["Content-Type": "application/json"])
        guard let candidates = data["candidates"] as? [[String: Any]],
              let content    = candidates.first?["content"] as? [String: Any],
              let parts      = content["parts"] as? [[String: Any]],
              let text       = parts.first?["text"] as? String else {
            throw AiApiError.decodingError("candidates[0].content.parts[0].text missing")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── HTTP helper ───────────────────────────────────────────────────────────────────────────

    private static func post(url: String, body: [String: Any],
                              headers: [String: String]) async throws -> [String: Any] {
        guard let reqURL = URL(string: url) else {
            throw AiApiError.decodingError("Invalid URL: \(url)")
        }
        var request        = URLRequest(url: reqURL, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AiApiError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }
        if !(200..<300).contains(status) {
            let msg = (json["error"] as? [String: Any])?["message"] as? String
                   ?? json["message"] as? String
                   ?? "HTTP \(status)"
            throw AiApiError.httpError(status, msg)
        }
        return json
    }
}
