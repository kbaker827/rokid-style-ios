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
