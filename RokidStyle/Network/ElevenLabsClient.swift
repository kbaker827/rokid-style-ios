import Foundation

// ── ElevenLabs TTS ────────────────────────────────────────────────────────────
// POST /v1/text-to-speech/{voice_id}  →  returns mp3 audio data
//
// Uses eleven_turbo_v2 for low-latency real-time voice output.
// Default voice: Rachel (neutral, clear US English — good for glasses audio).

enum ElevenLabsError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "ElevenLabs \(code): \(msg)"
        }
    }
}

struct ElevenLabsClient {

    /// Voice ID to use. Rachel is a clear, neutral US English voice.
    static let voiceId = "21m00Tcm4TlvDq8ikWAM"

    /// Synthesize `text` and return raw mp3 `Data`.
    static func synthesize(text: String, apiKey: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!
        var request        = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey,            forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg",       forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text":     text,
            "model_id": "eleven_turbo_v2",       // lowest latency
            "voice_settings": [
                "stability":        0.50,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw ElevenLabsError.httpError(status, msg)
        }
        return data
    }
}
