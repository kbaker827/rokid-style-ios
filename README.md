# Rokid Style AI

An iOS app that turns **Rokid Style** glasses into a hands-free AI assistant — no button presses, no screen interaction required.

## How it works

1. **Always listening** — the moment the app launches (and permissions are granted), the glasses' Bluetooth microphone streams continuously
2. **You speak** — a 1.8-second silence after your last word triggers the AI call
3. **AI responds** — your question is sent to the AI model of your choice; the answer is spoken back through the glasses' Bluetooth speakers via TTS
4. **Loop repeats** — the app automatically resumes listening 0.5 seconds after the TTS finishes

No button required. Just talk.

---

## Features

- **4 AI providers, 11 models** — OpenAI (GPT-4o, GPT-4o mini, o1 mini), Anthropic (Claude Opus / Sonnet / Haiku), Google (Gemini 2.0 Flash, 1.5 Pro/Flash), xAI (Grok 3, Grok 2)
- **Per-provider API keys** — stored securely in `UserDefaults`; easily swapped in Settings
- **Conversation memory** — keeps the last 20 messages as context so follow-up questions work naturally
- **TTS markdown stripping** — AI responses are cleaned of `**bold**`, `*italic*`, `` `code` `` and bullet points before being spoken so nothing sounds weird
- **Mute toggle** — pause/resume the always-on loop without killing the session
- **Editable system prompt** — default prompt instructs the AI to keep answers short and conversational (no lists or markdown)

---

## Requirements

- iPhone running **iOS 17+**
- Xcode 15+
- **Rokid Style** glasses paired via Bluetooth (any Bluetooth audio device will work)
- An API key for at least one of the supported providers

---

## Setup

1. Clone the repo and open `RokidStyle.xcodeproj` in Xcode
2. Select your development team in the project's Signing & Capabilities tab
3. Build and run on your iPhone (simulator won't work — Bluetooth + speech recognition require a real device)
4. Grant microphone and speech recognition permissions when prompted
5. Tap **Settings** (gear icon) → enter your API key → pick a model
6. Put on your glasses and start talking

---

## Project structure

```
RokidStyle/
├── App/
│   ├── RokidStyleApp.swift        @main entry point
│   └── Info.plist                 Permissions + background audio mode
├── UI/
│   ├── ContentView.swift          Status card, last Q&A, mute/clear controls
│   └── SettingsView.swift         Model picker, API key fields, system prompt
├── ViewModel/
│   └── StyleViewModel.swift       AppState machine, always-on voice loop
├── Audio/
│   ├── SpeechListener.swift       BT mic → SFSpeechRecognizer, silence detection
│   └── SpeechSynthesizer.swift    AVSpeechSynthesizer → BT speakers, markdown strip
├── Network/
│   └── AiApiClient.swift          URLSession clients for all 4 providers
└── Data/
    └── AiModels.swift             Providers, models, defaults, data types
```

---

## Supported models

| Provider | Models |
|----------|--------|
| OpenAI | GPT-4o, GPT-4o mini, o1 mini |
| Anthropic | Claude Opus 4.5, Sonnet 4.5, Haiku 3.5 |
| Google | Gemini 2.0 Flash, 1.5 Pro, 1.5 Flash |
| xAI | Grok 3, Grok 2 |

---

## Audio routing

iOS routes `AVAudioSession` configured as `.playAndRecord` / `.voiceChat` + `.allowBluetooth` to the active Bluetooth device automatically. This means:

- **Mic input** → glasses microphone (HFP profile, 8 kHz)
- **TTS output** → glasses speakers (A2DP or HFP depending on iOS selection)
- **Echo cancellation** → `.voiceChat` mode prevents TTS playback from being re-captured

No extra configuration needed — pair the glasses once via iOS Settings and the audio routes automatically.

---

## License

MIT
