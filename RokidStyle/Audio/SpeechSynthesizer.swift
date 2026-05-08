import AVFoundation

/// Speaks AI responses through the Rokid Style glasses Bluetooth speakers.
///
/// Because the `AVAudioSession` is already configured as `.playAndRecord` /
/// `.voiceChat` + `.allowBluetooth`, `AVSpeechSynthesizer` automatically
/// routes output to whichever Bluetooth device is active — i.e. the glasses.
final class SpeechSynthesizer: NSObject, ObservableObject {

    @Published var isSpeaking = false

    /// Called on the main thread when the utterance finishes (or is cancelled).
    var onFinished: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // ── Speak ─────────────────────────────────────────────────────────────────────────────────

    func speak(_ text: String) {
        guard !text.isEmpty else { onFinished?(); return }

        // Strip markdown artifacts (lists, bold, etc.) that sound bad when read aloud
        let clean = stripMarkdown(text)

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice           = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate            = 0.52          // slightly faster than default (0.5)
        utterance.pitchMultiplier = 1.0
        utterance.volume          = 1.0
        utterance.preUtteranceDelay  = 0.15       // small gap after the question
        utterance.postUtteranceDelay = 0.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // ── Markdown stripping ────────────────────────────────────────────────────────────────────
    // The system prompt instructs the AI not to use markdown, but as a safety net:

    private func stripMarkdown(_ text: String) -> String {
        var s = text
        // Remove **bold** and *italic*
        s = s.replacingOccurrences(of: "\\*{1,2}([^*]+)\\*{1,2}",
                                   with: "$1", options: .regularExpression)
        // Remove `code`
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        // Replace bullet points with a spoken pause
        s = s.replacingOccurrences(of: #"^\s*[-•*]\s+"#, with: " ", options: .regularExpression)
        // Remove #headings
        s = s.replacingOccurrences(of: #"^#+\s+"#, with: "", options: .regularExpression)
        return s
    }
}

// ── AVSpeechSynthesizerDelegate ───────────────────────────────────────────────────────────────

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
