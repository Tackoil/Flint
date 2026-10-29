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
    private let waitForTypingPause: @Sendable () async throws -> Void
    private var isComposing = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private(set) var query: TranslationQuery?
    private(set) var language: TranslationLanguage = .simplifiedChinese
    private(set) var state: State = .ready
    var onChange: (() -> Void)?

    init(client: any TranslationServing = DeepSeekTranslationClient(),
         waitForTypingPause: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(for: .milliseconds(600))
         },
         readAPIKey: @escaping () throws -> String? = { try TranslationAPIKeyStore().read() }) {
        self.client = client
        self.waitForTypingPause = waitForTypingPause
        self.readAPIKey = readAPIKey
    }

    func update(query: TranslationQuery?, language: TranslationLanguage, isComposing: Bool = false) {
        guard self.query != query || self.language != language || self.isComposing != isComposing else { return }
        cancel()
        self.query = query
        self.language = language
        self.isComposing = isComposing
        scheduleTranslation()
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
        generation += 1
        task?.cancel()
        task = nil
        state = .ready
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
                let answer = try await client.translate(text, to: language, apiKey: key)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.setState(.translated(answer))
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
