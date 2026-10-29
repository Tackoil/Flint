import Foundation

struct TranslationQuery: Equatable, Sendable {
    let text: String
    static let maximumLength = 12_000
}

enum TranslationLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "Simplified Chinese", traditionalChinese = "Traditional Chinese"
    case english = "English", japanese = "Japanese", korean = "Korean"
    case french = "French", german = "German", spanish = "Spanish", portuguese = "Portuguese"
    case italian = "Italian", russian = "Russian", arabic = "Arabic", hindi = "Hindi"
    case vietnamese = "Vietnamese", thai = "Thai"
}

final class TranslationPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var targetLanguage: TranslationLanguage {
        get {
            defaults.string(forKey: "translation.targetLanguage").flatMap(TranslationLanguage.init(rawValue:))
                ?? .simplifiedChinese
        }
        set { defaults.set(newValue.rawValue, forKey: "translation.targetLanguage") }
    }
}

enum TranslationError: Error, LocalizedError, Equatable {
    case missingAPIKey, tooLong, invalidResponse, incompleteResponse, authentication, balance, rateLimit
    case serviceUnavailable, requestRejected, network, timedOut

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your DeepSeek API key in Settings → Translation."
        case .tooLong: return "Translate up to 12,000 characters at a time. Shorten the text and try again."
        case .invalidResponse: return "DeepSeek returned an empty or unreadable translation. Try again."
        case .incompleteResponse: return "DeepSeek couldn’t finish the translation. Try a shorter passage."
        case .authentication: return "Your DeepSeek API key wasn’t accepted. Update it in Settings → Translation."
        case .balance: return "Your DeepSeek account has insufficient balance. Add funds on the DeepSeek platform."
        case .rateLimit: return "DeepSeek’s rate limit was reached. Wait a moment and try again."
        case .serviceUnavailable: return "DeepSeek is temporarily unavailable. Try again shortly."
        case .requestRejected: return "DeepSeek couldn’t process this request. Try different text."
        case .network: return "Couldn’t connect to DeepSeek. Check your internet connection and try again."
        case .timedOut: return "The translation timed out. Try again."
        }
    }
}
