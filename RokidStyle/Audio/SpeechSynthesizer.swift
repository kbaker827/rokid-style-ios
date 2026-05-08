import AVFoundation

/// Speaks AI responses through the Rokid Style glasses Bluetooth speakers.
///
/// Priority:
///   1. ElevenLabs (if `apikey_elevenlabs` is set in UserDefaults) — higher-quality
///      neural TTS; audio returned as mp3 and played via AVAudioPlayer.
///   2. AVSpeechSynthesizer — on-device fallback, no key required.
///
/// Both paths share the same AVAudioSession configured by SpeechListener
/// (.playAndRecord / .voiceChat + .allowBluetooth), so output automatically
/// routes to the glasses speakers.
final class SpeechSynthesizer: NSObject, ObservableObject {

    @Published var isSpeaking = false

    /// Called on the main thread when playback finishes or is cancelled by `stop()`.
    var onFinished: (() -> Void)?

    // ── AVSpeechSynthesizer (fallback) ────────────────────────────────────────
    private let avSynth = AVSpeechSynthesizer()

    // ── AVAudioPlayer (ElevenLabs path) ───────────────────────────────────────
    private var audioPlayer: AVAudioPlayer?

    override init() {
        super.init()
        avSynth.delegate = self
    }

    // ── Public API ────────────────────────────────────────────────────────────

    func speak(_ text: String) {
        guard !text.isEmpty else { onFinished?(); return }
        let clean = stripMarkdown(text)

        let elKey = UserDefaults.standard.string(forKey: "apikey_elevenlabs") ?? ""
        if !elKey.trimmingCharacters(in: .whitespaces).isEmpty {
            speakElevenLabs(clean, apiKey: elKey)
        } else {
            speakAV(clean)
        }
    }

    func stop() {
        // Stop ElevenLabs playback
        audioPlayer?.stop()
        audioPlayer = nil

        // Stop AVSpeechSynthesizer
        avSynth.stopSpeaking(at: .immediate)

        isSpeaking = false
        // Do NOT call onFinished — cancelled by user
    }

    // ── ElevenLabs path ───────────────────────────────────────────────────────

    private func speakElevenLabs(_ text: String, apiKey: String) {
        isSpeaking = true
        Task {
            do {
                let mp3 = try await ElevenLabsClient.synthesize(text: text, apiKey: apiKey)
                await playAudioData(mp3)
            } catch {
                // ElevenLabs failed (bad key, network, quota) → fall back to AVSynth
                await MainActor.run {
                    self.isSpeaking = false   // will be set true again in speakAV
                }
                speakAV(text)
            }
        }
    }

    @MainActor
    private func playAudioData(_ data: Data) {
        do {
            // Ensure audio session is active for Bluetooth routing
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isSpeaking  = true
        } catch {
            // Player setup failed → fall back to AVSynth
            isSpeaking = false
            speakAV(stripMarkdown(""))   // empty fallback — just signal finished
            onFinished?()
        }
    }

    // ── AVSpeechSynthesizer path (fallback) ───────────────────────────────────

    private func speakAV(_ text: String) {
        let utterance                    = AVSpeechUtterance(string: text)
        utterance.voice                  = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate                   = 0.52
        utterance.pitchMultiplier        = 1.0
        utterance.volume                 = 1.0
        utterance.preUtteranceDelay      = 0.15
        utterance.postUtteranceDelay     = 0.0
        isSpeaking = true
        avSynth.speak(utterance)
    }

    // ── Markdown stripping ────────────────────────────────────────────────────

    private func stripMarkdown(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "\\*{1,2}([^*]+)\\*{1,2}",
                                   with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\s*[-•*]\s+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
        return s
    }
}

// ── AVAudioPlayerDelegate (ElevenLabs finished) ───────────────────────────────

extension SpeechSynthesizer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer = nil
            self?.isSpeaking  = false
            self?.onFinished?()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer = nil
            self?.isSpeaking  = false
            self?.onFinished?()   // treat as finished so the loop continues
        }
    }
}

// ── AVSpeechSynthesizerDelegate (fallback finished) ───────────────────────────

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            self?.onFinished?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
            // Don't call onFinished — cancelled by user
        }
    }
}
