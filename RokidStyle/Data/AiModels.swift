import Foundation
import SwiftUI

// ── AI providers ──────────────────────────────────────────────────────────────────────────────

enum AiProvider: String, CaseIterable, Identifiable {
    case openAI    = "openai"
    case anthropic = "anthropic"
    case gemini    = "gemini"
    case grok      = "grok"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Google Gemini"
        case .grok:      return "xAI Grok"
        }
    }

    var shortName: String {
        switch self {
        case .openAI:    return "GPT"
        case .anthropic: return "Claude"
        case .gemini:    return "Gemini"
        case .grok:      return "Grok"
        }
    }

    var accentColor: Color {
        switch self {
        case .openAI:    return Color(red: 0.06, green: 0.64, blue: 0.50)   // #10A37F
        case .anthropic: return Color(red: 0.80, green: 0.47, blue: 0.36)   // #CC785C
        case .gemini:    return Color(red: 0.26, green: 0.52, blue: 0.96)   // #4285F4
        case .grok:      return Color(white: 0.85)
        }
    }

    var baseURL: String {
        switch self {
        case .openAI:    return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini:    return "https://generativelanguage.googleapis.com/v1beta"
        case .grok:      return "https://api.x.ai/v1"
        }
    }

    var apiKeyPref: String { "apikey_\(rawValue)" }
}

// ── Model catalogue ───────────────────────────────────────────────────────────────────────────

struct AiModel: Identifiable, Hashable {
    let id:          String   // exact API model identifier
    let displayName: String
    let provider:    AiProvider
}

let allModels: [AiModel] = [
    // OpenAI
    AiModel(id: "gpt-4o",                    displayName: "GPT-4o",            provider: .openAI),
    AiModel(id: "gpt-4o-mini",               displayName: "GPT-4o mini",       provider: .openAI),
    AiModel(id: "o1-mini",                   displayName: "o1 mini",           provider: .openAI),
    // Anthropic
    AiModel(id: "claude-opus-4-5",           displayName: "Claude Opus 4.5",   provider: .anthropic),
    AiModel(id: "claude-sonnet-4-5",         displayName: "Claude Sonnet 4.5", provider: .anthropic),
    AiModel(id: "claude-haiku-3-5",          displayName: "Claude Haiku 3.5",  provider: .anthropic),
    // Gemini
    AiModel(id: "gemini-2.0-flash",          displayName: "Gemini 2.0 Flash",  provider: .gemini),
    AiModel(id: "gemini-1.5-pro-latest",     displayName: "Gemini 1.5 Pro",    provider: .gemini),
    AiModel(id: "gemini-1.5-flash-latest",   displayName: "Gemini 1.5 Flash",  provider: .gemini),
    // Grok
    AiModel(id: "grok-3-latest",             displayName: "Grok 3",            provider: .grok),
    AiModel(id: "grok-2-latest",             displayName: "Grok 2",            provider: .grok),
]

func models(for provider: AiProvider) -> [AiModel] { allModels.filter { $0.provider == provider } }
func modelById(_ id: String) -> AiModel { allModels.first { $0.id == id } ?? allModels[0] }

// ── Conversation types ────────────────────────────────────────────────────────────────────────

struct ChatMessage: Codable {
    let role:    String   // "user" | "assistant" | "system"
    let content: String
}

struct ConversationEntry: Identifiable {
    let id        = UUID()
    let question:  String
    let answer:    String
    let modelName: String
}

// ── Defaults ──────────────────────────────────────────────────────────────────────────────────

let defaultSystemPrompt = """
You are a helpful AI assistant on Rokid Style glasses. \
The user is talking to you hands-free — your response will be read aloud. \
Keep answers conversational and under 3 sentences. \
No lists, no markdown, no asterisks. Speak naturally.
"""

let defaultModelId = "gpt-4o-mini"
