import AVFoundation
import Speech
import Combine

/// Continuously listens for speech via the Rokid Style glasses Bluetooth microphone.
///
/// Flow:
///  1. `start()` — configures Bluetooth audio session, begins recognition
///  2. Speech detected → `partialTranscript` updates live
///  3. 1.8 s silence after last word → `onFinalTranscript` fires, mic stops
///  4. Caller restarts by calling `start()` again after the AI responds
///
/// Audio routing: `.playAndRecord` / `.voiceChat` + `.allowBluetooth` causes iOS
/// to prefer the paired Bluetooth device (glasses) for both input and output.
final class SpeechListener: NSObject, ObservableObject {

    // ── Published state ───────────────────────────────────────────────────────────────────────
    @Published var isListening        = false
    @Published var partialTranscript  = ""
    @Published var isSpeechAvailable  = false

    // ── Callbacks (called on main thread) ─────────────────────────────────────────────────────
    var onFinalTranscript: ((String) -> Void)?
    var onError:           ((String) -> Void)?

    // ── Private ───────────────────────────────────────────────────────────────────────────────
    private let recognizer  = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine = AVAudioEngine()
    private var recogTask:   SFSpeechRecognitionTask?
    private var recogReq:    SFSpeechAudioBufferRecognitionRequest?
    private var silenceTimer: Timer?
    private var latestText   = ""

    override init() {
        super.init()
        recognizer?.delegate = self
        isSpeechAvailable    = recognizer?.isAvailable ?? false

        // Audio session interruption (phone call, Siri, etc.)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil
        )
    }

    // ── Permissions ───────────────────────────────────────────────────────────────────────────

    static func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let mic = await AVAudioApplication.requestRecordPermission()
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        return (mic, speech)
    }

    // ── Start / stop ──────────────────────────────────────────────────────────────────────────

    func start() {
        guard !isListening else { return }
        guard recognizer?.isAvailable == true else {
            onError?("Speech recognition not available on this device.")
            return
        }
        do {
            try configureBluetooth()
            try beginRecognition()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()

        recogTask?.cancel()
        recogReq?.endAudio()
        recogTask = nil
        recogReq  = nil
        latestText = ""

        DispatchQueue.main.async { [weak self] in
            self?.isListening       = false
            self?.partialTranscript = ""
        }
    }

    // ── Bluetooth audio session ───────────────────────────────────────────────────────────────

    private func configureBluetooth() throws {
        let session = AVAudioSession.sharedInstance()
        // .voiceChat enables echo cancellation so the glasses speakers don't feed back into the mic
        try session.setCategory(
            .playAndRecord,
            mode:    .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // ── Recognition ───────────────────────────────────────────────────────────────────────────

    private func beginRecognition() throws {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false   // online = better accuracy
        recogReq = req

        // Use the actual input format — adapts to Bluetooth (8 kHz HFP) automatically
        let node   = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recogReq?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        DispatchQueue.main.async { [weak self] in self?.isListening = true }

        recogTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            // SFSpeechRecognitionTask callbacks arrive on the main queue
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.latestText            = text
                self.partialTranscript     = text
                self.resetSilenceTimer()

                if result.isFinal, !text.isEmpty {
                    self.silenceTimer?.invalidate()
                    self.finalize()
                }
            }

            if let error {
                let code = (error as NSError).code
                // 1110 = kAFAssistantErrorDomain "no speech"
                // 203  = cancelled
                if code != 1110 && code != 203 {
                    self.onError?(error.localizedDescription)
                }
                // On "no speech" with no transcript, quietly reset so ViewModel can restart
                if self.latestText.isEmpty {
                    DispatchQueue.main.async { self.isListening = false }
                }
            }
        }
    }

    // ── Silence detection ─────────────────────────────────────────────────────────────────────

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        // 1.8 s of silence after the last recognised word → treat as end of utterance
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            guard let self, !self.latestText.isEmpty else { return }
            self.finalize()
        }
    }

    private func finalize() {
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        guard !text.isEmpty else { return }
        onFinalTranscript?(text)
    }

    // ── Interruption handling ─────────────────────────────────────────────────────────────────

    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began { stop() }
    }
}

// ── SFSpeechRecognizerDelegate ────────────────────────────────────────────────────────────────

extension SpeechListener: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async { [weak self] in self?.isSpeechAvailable = available }
    }
}
