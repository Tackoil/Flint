import Foundation

@MainActor
final class TranslationSession {
    enum State: Equatable {
        case ready, waiting, loading, translated(String), failed(String), needsAPIKey

        var answer: String? {
            guard case .translated(let text) = self else { return nil }
            return text
        }

        var canPerformAction: Bool {
            if case .failed = self { return true }
            return answer != nil || self == .needsAPIKey
        }
    }

    private let client: any TranslationServing
    private let readAPIKey: () throws -> String?
    private let inferSourceLanguage: (String) -> InferredSourceLanguage?
    private let waitForTypingPause: @Sendable () async throws -> Void
    private var isComposing = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private var responses: [TranslationLanguage: TranslationResponse] = [:]
    private(set) var query: TranslationQuery?
    private(set) var language: TranslationLanguage = .simplifiedChinese
    private(set) var sourceLanguage: InferredSourceLanguage?
    private(set) var state: State = .ready
    var onChange: (() -> Void)?

    init(client: any TranslationServing = DeepSeekTranslationClient(),
         inferSourceLanguage: @escaping (String) -> InferredSourceLanguage? = SourceLanguageInference.infer,
         waitForTypingPause: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(for: .milliseconds(600))
         },
         readAPIKey: @escaping () throws -> String? = { try TranslationAPIKeyStore().read() }) {
        self.client = client
        self.inferSourceLanguage = inferSourceLanguage
        self.waitForTypingPause = waitForTypingPause
        self.readAPIKey = readAPIKey
    }

    func update(query: TranslationQuery?, language: TranslationLanguage, isComposing: Bool = false) {
        guard self.query != query || self.language != language || self.isComposing != isComposing else { return }
        stopPendingTranslation()
        if self.query != query { responses.removeAll() }
        self.query = query
        self.language = language
        self.isComposing = isComposing
        if restoreCachedResponse() { return }
        scheduleTranslation()
    }

    func cachedResponse(for language: TranslationLanguage) -> TranslationResponse? {
        guard !isComposing else { return nil }
        return responses[language]
    }

    private func restoreCachedResponse() -> Bool {
        guard let response = cachedResponse(for: language) else { return false }
        sourceLanguage = response.sourceLanguage
        state = .translated(response.text)
        return true
    }

    private func scheduleTranslation() {
        guard let query, !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isComposing else { return }
        state = .waiting
        let current = generation
        let wait = waitForTypingPause
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                try await wait()
                try Task.checkCancellation()
                guard let self, self.generation == current else { return }
                self.task = nil
                self.submit()
            } catch { return }
        }
    }

    func cancel() {
        stopPendingTranslation()
        responses.removeAll()
    }

    private func stopPendingTranslation() {
        generation += 1
        task?.cancel()
        task = nil
        state = .ready
        sourceLanguage = nil
    }

    func submit() {
        guard let query, !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isComposing, state != .loading else { return }
        task?.cancel()
        task = nil
        guard query.text.count <= TranslationQuery.maximumLength else {
            setState(.failed(TranslationError.tooLong.localizedDescription))
            return
        }
        if restoreCachedResponse() { onChange?(); return }
        sourceLanguage = inferSourceLanguage(query.text)
        do {
            guard let key = try readAPIKey(), !key.isEmpty else {
                setState(.needsAPIKey)
                return
            }
            start(query.text, key: key)
        } catch {
            setState(.failed(error.localizedDescription))
        }
    }

    private func start(_ text: String, key: String) {
        generation += 1
        let current = generation
        setState(.loading)
        let language = language
        let client = client
        task = Task { [weak self] in
            do {
                let response = try await client.translate(text, to: language, apiKey: key)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.sourceLanguage = response.sourceLanguage ?? self.sourceLanguage
                self.responses[language] = TranslationResponse(text: response.text, sourceLanguage: self.sourceLanguage)
                self.setState(.translated(response.text))
            } catch {
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.receive(error)
            }
        }
    }

    private func receive(_ error: Error) {
        if let error = error as? TranslationError, [.authentication, .missingAPIKey].contains(error) {
            setState(.needsAPIKey)
        } else {
            setState(.failed(error.localizedDescription))
        }
    }

    private func setState(_ state: State) {
        self.state = state
        onChange?()
    }
}
