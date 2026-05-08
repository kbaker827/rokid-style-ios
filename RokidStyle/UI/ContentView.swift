import SwiftUI

struct ContentView: View {

    @StateObject private var vm = StyleViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Status card ───────────────────────────────────────────
                    StatusCard(appState: vm.appState, partial: vm.partialTranscript)
                        .padding(.horizontal)
                        .padding(.top)

                    // ── Last exchange ─────────────────────────────────────────
                    if !vm.lastQuestion.isEmpty || !vm.lastAnswer.isEmpty {
                        LastExchangeCard(question: vm.lastQuestion, answer: vm.lastAnswer)
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }

                    Spacer()

                    // ── Controls ──────────────────────────────────────────────
                    ControlBar(vm: vm)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Rokid Style AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(vm: vm)
            }
        }
    }
}

// ── Status card ───────────────────────────────────────────────────────────────

private struct StatusCard: View {
    let appState:  AppState
    let partial:   String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                StatusOrb(appState: appState)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.label)
                        .font(.headline)
                    Text(appState.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !partial.isEmpty {
                HStack {
                    Text(""\(partial)"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// ── Animated status orb ───────────────────────────────────────────────────────

private struct StatusOrb: View {
    let appState: AppState
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(orbColor.opacity(0.25))
                .frame(width: 52, height: 52)
                .scaleEffect(pulse ? 1.25 : 1.0)
                .animation(
                    orbPulses
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
            Circle()
                .fill(orbColor)
                .frame(width: 28, height: 28)
            Image(systemName: orbIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .onAppear  { if orbPulses { pulse = true } }
        .onChange(of: appState) { _, _ in pulse = orbPulses }
    }

    private var orbColor: Color {
        switch appState {
        case .permissionRequired:        return .orange
        case .idle:                      return .gray
        case .listening:                 return .green
        case .processing:                return .blue
        case .speaking:                  return .purple
        case .error:                     return .red
        }
    }
    private var orbIcon: String {
        switch appState {
        case .permissionRequired:        return "lock.fill"
        case .idle:                      return "pause.fill"
        case .listening:                 return "mic.fill"
        case .processing:                return "cpu"
        case .speaking:                  return "speaker.wave.2.fill"
        case .error:                     return "exclamationmark"
        }
    }
    private var orbPulses: Bool {
        switch appState {
        case .listening, .processing, .speaking: return true
        default: return false
        }
    }
}

// ── Last exchange card ────────────────────────────────────────────────────────

private struct LastExchangeCard: View {
    let question: String
    let answer:   String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !question.isEmpty {
                Label {
                    Text(question)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
            if !answer.isEmpty {
                Divider()
                Label {
                    Text(answer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// ── Control bar ───────────────────────────────────────────────────────────────

private struct ControlBar: View {
    @ObservedObject var vm: StyleViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Mute toggle
            Button {
                vm.toggleMute()
            } label: {
                Label(
                    vm.isMuted ? "Unmute" : "Mute",
                    systemImage: vm.isMuted ? "mic.slash.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.isMuted ? .orange : .green)
            .controlSize(.large)

            // Clear history
            Button {
                vm.clearHistory()
            } label: {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

// ── AppState display helpers ──────────────────────────────────────────────────

private extension AppState {
    var label: String {
        switch self {
        case .permissionRequired:       return "Permissions needed"
        case .idle:                     return "Paused"
        case .listening:                return "Listening…"
        case .processing:               return "Thinking…"
        case .speaking:                 return "Speaking"
        case .error:                    return "Error"
        }
    }
    var subtitle: String {
        switch self {
        case .permissionRequired:       return "Open Settings to grant mic & speech access"
        case .idle:                     return "Tap Unmute to resume"
        case .listening:                return "Say something to your glasses"
        case .processing:               return "Calling AI…"
        case .speaking:                 return "Playing response through glasses"
        case .error(let msg):           return msg
        }
    }
}

// ── Preview ───────────────────────────────────────────────────────────────────

#Preview {
    ContentView()
}
