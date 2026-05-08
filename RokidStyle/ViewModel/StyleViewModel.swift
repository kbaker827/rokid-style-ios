import Foundation
import Combine

// ── State machine ─────────────────────────────────────────────────────────────────────────────
enum AppState: Equatable {
    case permissionRequired
    case idle               // paused by user
    case listening          // mic active, waiting for speech
    case processing         // API call in flight
    case speaking           // TTS playing response
    case error(String)
}

// ── ViewModel ─────────────────────────────────────────────────────────────────────────────────

@MainActor
final class StyleViewModel: ObservableObject {

    // ── Published state ───────────────────────────────────────────────────────────────────────
    @Published var appState:          AppState = .permissionRequired
    @Published var partialTranscript: String   = ""
    @Published var lastQuestion:      String   = ""
    @Published var lastAnswer:        String   = ""
    @Published var history:           [ConversationEntry] = []
    @Published var isMuted:           Bool     = false  // user-triggered pause

    // ── Settings (persisted) ──────────────────────────────────────────────────────────────────
    @Published var selectedModelId: String {
        didSet { UserDefaults.standard.set(selectedModelId, forKey: "selectedModel") }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }

    var selectedModel: AiModel { modelById(selectedModelId) }

    func apiKey(for provider: AiProvider) -> String {
        UserDefaults.standard.string(forKey: provider.apiKeyPref) ?? ""
    }
    func setApiKey(_ key: String, for provider: AiProvider) {
        UserDefaults.standard.set(key, forKey: provider.apiKeyPref)
    }

    // ── Audio ─────────────────────────────────────────────────────────────────────────────────
    let listener    = SpeechListener()
    let synthesizer = SpeechSynthesizer()

    // ── Conversation context ──────────────────────────────────────────────────────────────────
    private var chatHistory: [ChatMessage] = []

    // ── Init ──────────────────────────────────────────────────────────────────────────────────

    init() {
        selectedModelId = UserDefaults.standard.string(forKey: "selectedModel") ?? defaultModelId
        systemPrompt    = UserDefaults.standard.string(forKey: "systemPrompt")  ?? defaultSystemPrompt

        wireAudio()

        Task { await requestPermissionsAndStart() }
    }

    // ── Permission + auto-start ───────────────────────────────────────────────────────────────

    private func requestPermissionsAndStart() async {
        let (mic, speech) = await SpeechListener.requestPermissions()
        if mic && speech {
            startListeningLoop()
        } else {
            appState = .permissionRequired
        }
    }

    // ── Wire audio callbacks ──────────────────────────────────────────────────────────────────

    private func wireAudio() {
        // Partial transcript → update UI live
        listener.onFinalTranscript = { [weak self] text in
            self?.handleTranscript(text)
        }
        listener.onError = { [weak self] msg in
            guard let self else { return }
            // "No speech" silences (empty transcript) → quietly restart
            if self.listener.partialTranscript.isEmpty && !self.isMuted {
                self.startListeningLoop()
            } else {
                self.appState = .error(msg)
            }
        }

        // TTS finished → restart listening automatically
        synthesizer.onFinished = { [weak self] in
            guard let self, !self.isMuted else { return }
            // Brief pause before reactivating mic (avoids echo of last TTS syllable)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startListeningLoop()
            }
        }
    }

    // ── Listening loop ────────────────────────────────────────────────────────────────────────

    func startListeningLoop() {
        guard !isMuted else { appState = .idle; return }
        appState = .listening
        listener.start()
    }

    func stopEverything() {
        listener.stop()
        synthesizer.stop()
        appState = .idle
    }

    /// Toggle mute — pauses the always-on loop
    func toggleMute() {
        isMuted = !isMuted
        if isMuted {
            stopEverything()
        } else {
            startListeningLoop()
        }
    }

    func clearHistory() {
        chatHistory.removeAll()
        history.removeAll()
        lastQuestion = ""
        lastAnswer   = ""
    }

    // ── Transcript → AI ───────────────────────────────────────────────────────────────────────

    private func handleTranscript(_ text: String) {
        lastQuestion     = text
        partialTranscript = ""
        appState         = .processing

        chatHistory.append(ChatMessage(role: "user", content: text))
        if chatHistory.count > 20 { chatHistory.removeFirst() }

        let model  = selectedModel
        let key    = apiKey(for: model.provider)
        let system = systemPrompt

        Task {
            do {
                let answer = try await AiApiClient.complete(
                    model:        model,
                    apiKey:       key,
                    messages:     chatHistory,
                    systemPrompt: system.isEmpty ? nil : system
                )

                chatHistory.append(ChatMessage(role: "assistant", content: answer))
                if chatHistory.count > 20 { chatHistory.removeFirst() }

                lastAnswer = answer
                history.append(ConversationEntry(question: text, answer: answer,
                                                 modelName: model.displayName))
                if history.count > 50 { history.removeFirst() }

                appState = .speaking
                synthesizer.speak(answer)

            } catch {
                let msg = error.localizedDescription
                lastAnswer = msg
                appState   = .error(msg)
                // Speak the error so the user knows without looking at the phone
                synthesizer.speak("Sorry, I ran into a problem. \(shortError(msg))")
            }
        }
    }

    /// Condense a long error string to something speakable
    private func shortError(_ full: String) -> String {
        if full.contains("API key") || full.contains("No API key") { return "Please check your API key in Settings." }
        if full.contains("network") || full.contains("offline")    { return "Please check your internet connection." }
        return "Please try again."
    }
}
