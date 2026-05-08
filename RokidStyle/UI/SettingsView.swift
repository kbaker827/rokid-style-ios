import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: StyleViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // ── Model selection ────────────────────────────────────────
                Section {
                    ForEach(AiProvider.allCases) { provider in
                        DisclosureGroup {
                            ForEach(models(for: provider)) { model in
                                HStack {
                                    Text(model.displayName)
                                        .font(.subheadline)
                                    Spacer()
                                    if vm.selectedModelId == model.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accentColor)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { vm.selectedModelId = model.id }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(provider.accentColor)
                                    .frame(width: 10, height: 10)
                                Text(provider.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if models(for: provider).contains(where: { $0.id == vm.selectedModelId }) {
                                    Text(vm.selectedModel.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("AI Model")
                } footer: {
                    Text("Selected: \(vm.selectedModel.displayName)")
                }

                // ── API keys ───────────────────────────────────────────────
                Section("API Keys") {
                    ForEach(AiProvider.allCases) { provider in
                        ApiKeyRow(provider: provider, vm: vm)
                    }
                }

                // ── System prompt ──────────────────────────────────────────
                Section {
                    TextEditor(text: $vm.systemPrompt)
                        .font(.callout)
                        .frame(minHeight: 120)
                    Button("Reset to default") {
                        vm.systemPrompt = defaultSystemPrompt
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Tip: keep it short — responses are spoken aloud. Longer prompts use more tokens.")
                }

                // ── Voice (TTS) ───────────────────────────────────────────
                ElevenLabsSection()

                // ── About ──────────────────────────────────────────────────
                Section("About") {
                    LabeledContent("App", value: "Rokid Style AI")
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Device", value: "Rokid Style Glasses")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// ── ElevenLabs section (key + voice picker) ───────────────────────────────────

private struct ElevenLabsSection: View {

    private let elOrange = Color(red: 0.98, green: 0.47, blue: 0.22)

    @State private var keyText:         String            = ""
    @State private var isRevealed:      Bool              = false
    @State private var voices:          [ElevenLabsVoice] = []
    @State private var selectedVoiceId: String            = ElevenLabsClient.defaultVoiceId
    @State private var loadState:       LoadState         = .idle

    private enum LoadState { case idle, loading, loaded, failed(String) }

    private var hasKey: Bool { !keyText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Section {
            // ── API key row ────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .foregroundStyle(elOrange)
                    .font(.caption)
                Group {
                    if isRevealed {
                        TextField("ElevenLabs API key", text: $keyText)
                            .font(.callout.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField("ElevenLabs API key", text: $keyText)
                            .font(.callout)
                    }
                }
                .onChange(of: keyText) { _, new in
                    UserDefaults.standard.set(new, forKey: "apikey_elevenlabs")
                    if hasKey { loadVoices() } else { voices = []; loadState = .idle }
                }
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            // ── Voice picker ───────────────────────────────────────────────
            if hasKey {
                switch loadState {
                case .idle:
                    EmptyView()

                case .loading:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading voices…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                case .loaded:
                    Picker(selection: $selectedVoiceId) {
                        ForEach(voices) { voice in
                            Text(voice.name).tag(voice.voice_id)
                        }
                    } label: {
                        Label("Voice", systemImage: "person.wave.2")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedVoiceId) { _, new in
                        UserDefaults.standard.set(new, forKey: ElevenLabsClient.voiceIdPref)
                    }

                case .failed(let msg):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") { loadVoices() }
                            .font(.caption)
                    }
                }
            }

        } header: {
            Text("Voice (TTS)")
        } footer: {
            if hasKey {
                Text("Using ElevenLabs neural TTS. Falls back to on-device voice if unavailable.")
            } else {
                Text("Add an ElevenLabs key to use neural TTS through your glasses. Leave blank to use the free on-device voice.")
            }
        }
        .onAppear {
            keyText         = UserDefaults.standard.string(forKey: "apikey_elevenlabs") ?? ""
            selectedVoiceId = UserDefaults.standard.string(forKey: ElevenLabsClient.voiceIdPref) ?? ElevenLabsClient.defaultVoiceId
            if hasKey { loadVoices() }
        }
    }

    private func loadVoices() {
        let key = keyText.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        loadState = .loading
        Task {
            do {
                let fetched = try await ElevenLabsClient.fetchVoices(apiKey: key)
                await MainActor.run {
                    voices    = fetched
                    // Keep existing selection if it's still in the list, otherwise pick first
                    if !fetched.contains(where: { $0.voice_id == selectedVoiceId }),
                       let first = fetched.first {
                        selectedVoiceId = first.voice_id
                        UserDefaults.standard.set(first.voice_id, forKey: ElevenLabsClient.voiceIdPref)
                    }
                    loadState = .loaded
                }
            } catch {
                await MainActor.run {
                    loadState = .failed(error.localizedDescription)
                }
            }
        }
    }
}

// ── API key row ───────────────────────────────────────────────────────────────

private struct ApiKeyRow: View {
    let provider:  AiProvider
    @ObservedObject var vm: StyleViewModel

    @State private var keyText: String = ""
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(provider.accentColor)
                .frame(width: 8, height: 8)
            Group {
                if isRevealed {
                    TextField(provider.displayName + " key", text: $keyText)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField(provider.displayName + " key", text: $keyText)
                        .font(.callout)
                }
            }
            .onChange(of: keyText) { _, new in
                vm.setApiKey(new, for: provider)
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .onAppear { keyText = vm.apiKey(for: provider) }
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    SettingsView(vm: StyleViewModel())
}
