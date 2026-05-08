import Foundation

// ── ElevenLabs TTS ────────────────────────────────────────────────────────────
// POST /v1/text-to-speech/{voice_id}  →  returns mp3 audio data
// GET  /v1/voices                     →  returns available voices
//
// Uses eleven_turbo_v2 for low-latency real-time voice output.

// ── Data types ────────────────────────────────────────────────────────────────

struct ElevenLabsVoice: Identifiable, Decodable, Hashable {
    let voice_id: String
    let name:     String
    var id: String { voice_id }
}

enum ElevenLabsError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): return "ElevenLabs \(code): \(msg)"
        }
    }
}

// ── Client ────────────────────────────────────────────────────────────────────

struct ElevenLabsClient {

    /// Fallback voice ID (Rachel — neutral US English) used when no voice is selected.
    static let defaultVoiceId   = "21m00Tcm4TlvDq8ikWAM"
    static let defaultVoiceName = "Rachel"

    /// UserDefaults key for the persisted voice ID selection.
    static let voiceIdPref = "elevenlabs_voice_id"

    /// The currently selected voice ID (from UserDefaults, or the default).
    static var selectedVoiceId: String {
        UserDefaults.standard.string(forKey: voiceIdPref) ?? defaultVoiceId
    }

    // ── Fetch available voices ─────────────────────────────────────────────────

    /// Returns the full list of voices available on the account.
    /// Sorted alphabetically by name.
    static func fetchVoices(apiKey: String) async throws -> [ElevenLabsVoice] {
        let url = URL(string: "https://api.elevenlabs.io/v1/voices")!
        var request        = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(apiKey,            forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw ElevenLabsError.httpError(status, msg)
        }

        struct VoicesResponse: Decodable { let voices: [ElevenLabsVoice] }
        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return decoded.voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // ── Synthesize ────────────────────────────────────────────────────────────

    /// Synthesize `text` using the given `voiceId` and return raw mp3 `Data`.
    static func synthesize(text: String, apiKey: String, voiceId: String? = nil) async throws -> Data {
        let vid = voiceId ?? selectedVoiceId
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(vid)")!
        var request        = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey,             forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg",        forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text":     text,
            "model_id": "eleven_turbo_v2",        // lowest latency
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
