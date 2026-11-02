import Foundation
import NaturalLanguage

struct InferredSourceLanguage: Equatable, Sendable {
    enum Origin: Sendable { case local, deepSeek }
    let code: String
    let origin: Origin

    init(code: String, origin: Origin = .local) {
        self.code = code
        self.origin = origin
    }

    static func fromDeepSeek(_ value: String?) -> InferredSourceLanguage? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        guard code.count <= 35,
              code.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil else { return nil }
        let canonical = Locale.canonicalLanguageIdentifier(from: code)
        let base = canonical.split(separator: "-").first.map(String.init) ?? ""
        guard !["und", "zxx"].contains(base),
              Locale.LanguageCode.isoLanguageCodes.contains(where: { $0.identifier == base }) else { return nil }
        return InferredSourceLanguage(code: canonical, origin: .deepSeek)
    }

    var displayName: String {
        let chinese = ["zh-Hans": "Simplified Chinese", "zh-Hant": "Traditional Chinese"]
        return chinese[code] ?? Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}

struct TranslationResponse: Equatable, Sendable {
    let text: String
    let sourceLanguage: InferredSourceLanguage?
    let explanation: String?
    let alternateMeanings: [String]

    init(text: String, sourceLanguage: InferredSourceLanguage?, explanation: String? = nil,
         alternateMeanings: [String] = []) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        let explanation = explanation?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.explanation = explanation?.isEmpty == false ? explanation : nil
        self.alternateMeanings = alternateMeanings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum SourceLanguageInference {
    static func infer(_ text: String) -> InferredSourceLanguage? {
        let sample = String(text.prefix(TranslationQuery.maximumLength))
        guard sample.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return confidentLanguage(in: recognizer.languageHypotheses(withMaximum: 2))
    }

    static func confidentLanguage(in hypotheses: [NLLanguage: Double]) -> InferredSourceLanguage? {
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.key != .undetermined, best.value >= 0.65 else { return nil }
        return InferredSourceLanguage(code: best.key.rawValue)
    }
}

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

    func matches(_ source: InferredSourceLanguage) -> Bool {
        let codes: [Self: String] = [
            .simplifiedChinese: "zh-Hans", .traditionalChinese: "zh-Hant", .english: "en",
            .japanese: "ja", .korean: "ko", .french: "fr", .german: "de", .spanish: "es",
            .portuguese: "pt", .italian: "it", .russian: "ru", .arabic: "ar", .hindi: "hi",
            .vietnamese: "vi", .thai: "th"
        ]
        let detected = Locale.Language(identifier: source.code)
        let target = Locale.Language(identifier: codes[self]!)
        guard detected.languageCode == target.languageCode else { return false }
        return target.languageCode?.identifier != "zh" || detected.script == target.script
    }

    static func targets(in saved: [Self], excluding source: InferredSourceLanguage?) -> [Self] {
        guard let source else { return saved }
        let targets = saved.filter { !$0.matches(source) }
        return targets.isEmpty ? [Self.english.matches(source) ? .simplifiedChinese : .english] : targets
    }
}

final class TranslationPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var targetLanguage: TranslationLanguage {
        get {
            defaults.string(forKey: "translation.targetLanguage").flatMap(TranslationLanguage.init(rawValue:))
                ?? .simplifiedChinese
        }
        set {
            defaults.set(newValue.rawValue, forKey: "translation.targetLanguage")
            guard defaults.array(forKey: "translation.targetLanguages") != nil else { return }
            if !targetLanguages.contains(newValue) { targetLanguages.append(newValue) }
        }
    }

    var targetLanguages: [TranslationLanguage] {
        get {
            let stored = defaults.stringArray(forKey: "translation.targetLanguages") ?? []
            let languages = uniqueLanguages(stored.compactMap(TranslationLanguage.init(rawValue:)))
            return languages.isEmpty ? [targetLanguage] : languages
        }
        set {
            let languages = uniqueLanguages(newValue)
            guard let first = languages.first else { return }
            defaults.set(languages.map(\.rawValue), forKey: "translation.targetLanguages")
            if !languages.contains(targetLanguage) { targetLanguage = first }
        }
    }

    private func uniqueLanguages(_ languages: [TranslationLanguage]) -> [TranslationLanguage] {
        var result: [TranslationLanguage] = []
        for language in languages where !result.contains(language) { result.append(language) }
        return result
    }

    func availableTargets(excluding source: InferredSourceLanguage?) -> [TranslationLanguage] {
        TranslationLanguage.targets(in: targetLanguages, excluding: source)
    }

    func targetLanguage(shiftedBy offset: Int, excluding source: InferredSourceLanguage? = nil,
                        from selected: TranslationLanguage? = nil) -> TranslationLanguage {
        let languages = availableTargets(excluding: source)
        let current = languages.firstIndex(of: selected ?? targetLanguage) ?? 0
        let index = (current + offset % languages.count + languages.count) % languages.count
        return languages[index]
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
