import Foundation
import NaturalLanguage
import Testing
@testable import FlintCore

struct TranslationTests {
    @Test(arguments: ["t", "tr", "trans", "translate", " TRANSLATE ", "late", "tl"])
    func translateActionUsesNormalSearchMatching(_ text: String) {
        #expect(ApplicationSearch.filter([LauncherItem.translation], query: text) == [.translation])
        #expect(LauncherItem.translation.kind == "Action")
    }

    @Test(arguments: ["translator", "translate hello", "Finder"])
    func unrelatedSearchesDoNotFindTranslate(_ text: String) {
        #expect(ApplicationSearch.filter([LauncherItem.translation], query: text).isEmpty)
    }

    @Test func languagePersistsAndInvalidValuesFallBack() throws {
        let suite = "FlintTranslationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = TranslationPreferences(defaults: defaults)
        #expect(preferences.targetLanguage == .simplifiedChinese)
        preferences.targetLanguage = .english
        #expect(TranslationPreferences(defaults: defaults).targetLanguage == .english)
        defaults.set("invalid", forKey: "translation.targetLanguage")
        #expect(preferences.targetLanguage == .simplifiedChinese)
    }

    @Test func sendsTranslationToDeepSeekWithExplicitTarget() async throws {
        let requests = TranslationRequestCounter()
        let client = DeepSeekTranslationClient { request in
            await requests.record()
            #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.timeoutInterval == 60)
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(body["model"] as? String == "deepseek-flash")
            #expect(body["stream"] as? Bool == false)
            #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
            #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
            let messages = try #require(body["messages"] as? [[String: String]])
            #expect(messages[0]["content"]?.contains("Japanese") == true)
            #expect(messages[0]["content"]?.contains("source_language") == true)
            #expect(messages[1] == ["role": "user", "content": "Hello\nworld"])
            return try translationResponse("こんにちは\n世界", sourceLanguage: "en")
        }
        let result = try await client.translate("Hello\nworld", to: .japanese, apiKey: " test-key ")
        #expect(result.text == "こんにちは\n世界")
        #expect(result.sourceLanguage == .init(code: "en", origin: .deepSeek))
        #expect(await requests.count == 1)
    }

    @Test(arguments: [401, 403, 402, 429, 500, 503, 400, 422])
    func explainsHTTPFailures(_ status: Int) async {
        let client = DeepSeekTranslationClient { _ in response("private provider detail", status: status) }
        let errors: [Int: TranslationError] = [401: .authentication, 403: .authentication, 402: .balance,
            429: .rateLimit, 500: .serviceUnavailable, 503: .serviceUnavailable, 400: .requestRejected, 422: .requestRejected]
        await #expect(throws: errors[status]!) {
            try await client.translate("Hello", to: .english, apiKey: "test-key")
        }
    }

    @Test(arguments: ["{}", "not json", #"{"choices":[]}"#,
                      #"{"choices":[{"message":{"content":" "},"finish_reason":"stop"}]}"#,
                      #"{"choices":[{"message":{"content":null},"finish_reason":"stop"}]}"#])
    func rejectsInvalidResponses(_ body: String) async {
        let client = DeepSeekTranslationClient { _ in response(body) }
        await #expect(throws: TranslationError.invalidResponse) {
            try await client.translate("Hello", to: .english, apiKey: "test-key")
        }
    }

    @Test(arguments: ["length", "content_filter", "aborted", "insufficient_system_resource"])
    func neverCopiesIncompleteTranslations(_ reason: String) async {
        let client = DeepSeekTranslationClient { _ in
            response("{\"choices\":[{\"message\":{\"content\":\"partial\"},\"finish_reason\":\"\(reason)\"}]}")
        }
        await #expect(throws: TranslationError.incompleteResponse) {
            try await client.translate("Hello", to: .english, apiKey: "test-key")
        }
    }

    @Test func validatesBeforeMakingRequests() async {
        let client = DeepSeekTranslationClient { _ in
            Issue.record("Invalid input must not be sent to DeepSeek")
            return response("{}")
        }
        await #expect(throws: TranslationError.missingAPIKey) {
            try await client.translate("Hello", to: .english, apiKey: " ")
        }
        await #expect(throws: TranslationError.tooLong) {
            try await client.translate(String(repeating: "a", count: 12_001), to: .english, apiKey: "test")
        }
        await #expect(throws: TranslationError.requestRejected) {
            try await client.translate(" \n ", to: .english, apiKey: "test")
        }
    }

    @Test func mapsNetworkFailuresAndPreservesCancellation() async {
        let timeout = DeepSeekTranslationClient { _ in throw URLError(.timedOut) }
        await #expect(throws: TranslationError.timedOut) {
            try await timeout.translate("Hello", to: .english, apiKey: "test")
        }
        let offline = DeepSeekTranslationClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: TranslationError.network) {
            try await offline.translate("Hello", to: .english, apiKey: "test")
        }
        let cancelled = DeepSeekTranslationClient { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) {
            try await cancelled.translate("Hello", to: .english, apiKey: "test")
        }
    }

    @Test(arguments: ["not json", "{}", #"{"translation":null}"#, #"{"translation":123}"#,
                      #"{"translation":" \n ","source_language":"en"}"#])
    func rejectsMalformedTranslationPayloads(_ content: String) async {
        let client = DeepSeekTranslationClient { _ in
            let body = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content], "finish_reason": "stop"]]
            ])
            return (body, response("").1)
        }
        await #expect(throws: TranslationError.invalidResponse) {
            try await client.translate("Hello", to: .japanese, apiKey: "test")
        }
    }

    @Test(arguments: ["und", "", "zz", "not-a-language", "<script>"])
    func badLanguageMetadataDoesNotDiscardAValidTranslation(_ code: String) async throws {
        let client = DeepSeekTranslationClient { _ in try translationResponse("Bonjour", sourceLanguage: code) }
        let result = try await client.translate("Hello", to: .french, apiKey: "test")
        #expect(result.text == "Bonjour")
        #expect(result.sourceLanguage == nil)
    }

    @Test func missingOrMistypedLanguageMetadataKeepsTheTranslation() async throws {
        let client = DeepSeekTranslationClient { _ in
            let content = #"{"translation":"Bonjour","source_language":123}"#
            let data = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content], "finish_reason": "stop"]]
            ])
            return (data, response("").1)
        }
        let result = try await client.translate("Hello", to: .french, apiKey: "test")
        #expect(result.text == "Bonjour" && result.sourceLanguage == nil)
    }
}

private actor TranslationRequestCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

struct SourceLanguageInferenceTests {
    @Test(arguments: [
        ("This is a complete English sentence about translating a message into another language.", "en"),
        ("这是一段中文文本，我们希望自动识别它的来源语言，然后把内容翻译成英文。", "zh-Hans"),
        ("これは日本語の文章です。入力した文章の言語を自動的に判別して、翻訳結果に表示します。", "ja"),
        ("Bonjour, ceci est un texte français qui permet de reconnaître automatiquement la langue du message.", "fr")
    ])
    func infersSourceLanguage(sample: (String, String)) {
        #expect(SourceLanguageInference.infer(sample.0)?.code == sample.1)
    }

    @Test(arguments: ["", " \n ", "12345 !!!", "👋🌏", "2026-10-29T12:00:00Z"])
    func avoidsInferringFromNonlinguisticInput(_ text: String) {
        #expect(SourceLanguageInference.infer(text) == nil)
    }

    @Test func uncertainOrUndeterminedLanguagesStayUnknown() {
        #expect(SourceLanguageInference.confidentLanguage(in: [:]) == nil)
        #expect(SourceLanguageInference.confidentLanguage(in: [.english: 0.6, .french: 0.4]) == nil)
        #expect(SourceLanguageInference.confidentLanguage(in: [.undetermined: 1]) == nil)
        #expect(SourceLanguageInference.confidentLanguage(in: [.english: 0.9, .french: 0.1])?.code == "en")
    }

    @Test func languageNamesAreReadableAndChineseScriptsStayDistinct() {
        #expect(InferredSourceLanguage(code: "en").displayName == "English")
        #expect(InferredSourceLanguage(code: "zh-Hans").displayName == "Simplified Chinese")
        #expect(InferredSourceLanguage(code: "zh-Hant").displayName == "Traditional Chinese")
    }

    @Test(arguments: [("EN", "en"), ("zh_Hant", "zh-Hant"), ("en-US", "en-US"), ("mul", "mul")])
    func validatesAndNormalizesDeepSeekLanguageCodes(example: (String, String)) {
        let source = InferredSourceLanguage.fromDeepSeek(example.0)
        #expect(source?.code == example.1)
        #expect(source?.origin == .deepSeek)
    }
}

private func response(_ body: String, status: Int = 200) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://api.deepseek.com/chat/completions")!,
                                    statusCode: status, httpVersion: nil, headerFields: nil)!)
}

private func translationResponse(_ translation: String, sourceLanguage: String? = nil) throws -> (Data, URLResponse) {
    var payload = ["translation": translation]
    payload["source_language"] = sourceLanguage
    let content = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    let data = try JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": content], "finish_reason": "stop"]]
    ])
    return (data, response("").1)
}

private actor DeferredTranslationClient: TranslationServing {
    private(set) var requests: [String] = []
    private var pending: [String: CheckedContinuation<TranslationResponse, any Error>] = [:]
    private var started: [String] = []
    private var observer: CheckedContinuation<String, Never>?

    func translate(_ text: String, to language: TranslationLanguage, apiKey: String) async throws -> TranslationResponse {
        requests.append(text)
        return try await withCheckedThrowingContinuation { continuation in
            pending[text] = continuation
            if let observer {
                self.observer = nil
                observer.resume(returning: text)
            } else { started.append(text) }
        }
    }

    func nextRequest() async -> String {
        if !started.isEmpty { return started.removeFirst() }
        return await withCheckedContinuation { observer = $0 }
    }

    func complete(_ text: String, answer: String, sourceLanguage: InferredSourceLanguage? = nil) {
        pending.removeValue(forKey: text)?.resume(returning: TranslationResponse(text: answer, sourceLanguage: sourceLanguage))
    }
}

private actor ControlledTypingPause {
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var started: [Int] = []
    private var observer: CheckedContinuation<Int, Never>?

    func wait() async throws {
        let id = nextID
        nextID += 1
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            if let observer {
                self.observer = nil
                observer.resume(returning: id)
            } else { started.append(id) }
        }
    }

    func nextPause() async -> Int {
        if !started.isEmpty { return started.removeFirst() }
        return await withCheckedContinuation { observer = $0 }
    }

    func finish(_ id: Int) { pending.removeValue(forKey: id)?.resume() }
}

@MainActor
struct TranslationSessionTests {
    @Test func missingKeyAndLengthErrorsAreActionable() {
        let session = TranslationSession(readAPIKey: { nil })
        session.update(query: .init(text: "Hello"), language: .english)
        session.submit()
        #expect(session.state == .needsAPIKey)
        session.update(query: .init(text: String(repeating: "a", count: 12_001)), language: .english)
        session.submit()
        #expect(session.state == .failed(TranslationError.tooLong.localizedDescription))
        session.update(query: .init(text: ""), language: .english)
        session.submit()
        #expect(session.state == .ready)
    }

    @Test func editingCancelsAndOldRequestsCannotReplaceNewResults() async {
        let client = DeferredTranslationClient()
        let session = TranslationSession(client: client,
                                         inferSourceLanguage: { .init(code: $0 == "old" ? "en" : "fr") },
                                         readAPIKey: { "test" })
        session.update(query: .init(text: "old"), language: .english)
        session.submit()
        #expect(session.state == .loading)
        #expect(session.sourceLanguage?.code == "en")
        #expect(await client.nextRequest() == "old")
        session.update(query: .init(text: "new"), language: .english)
        #expect(session.state == .waiting)
        #expect(session.sourceLanguage == nil)
        session.submit()
        #expect(await client.nextRequest() == "new")
        await withCheckedContinuation { done in
            session.onChange = {
                if session.state == .translated("fresh") { done.resume() }
            }
            Task { await client.complete("new", answer: "fresh") }
        }
        await client.complete("old", answer: "stale")
        // Yield until the old task has had a chance to deliver its cancelled result.
        for _ in 0..<20 { await Task.yield() }
        #expect(session.state.answer == "fresh")
        #expect(session.sourceLanguage?.code == "fr")
        session.onChange = nil
        session.cancel()
        #expect(session.state == .ready)
        #expect(session.state.answer == nil)
        #expect(session.sourceLanguage == nil)
    }

    @Test func targetChangesInvalidateTheAnswer() async {
        let client = DeepSeekTranslationClient { _ in try translationResponse("Hello") }
        let session = TranslationSession(client: client, readAPIKey: { "test" })
        session.update(query: .init(text: "你好"), language: .english)
        await withCheckedContinuation { done in
            session.onChange = {
                if session.state.answer != nil { done.resume() }
            }
            session.submit()
        }
        #expect(session.state.answer == "Hello")
        session.update(query: .init(text: "你好"), language: .japanese)
        #expect(session.state == .waiting)
        #expect(session.language == .japanese)
        session.cancel()
    }

    @Test func typingRestartsThePauseAndOnlyLatestTextIsSentAutomatically() async {
        let pause = ControlledTypingPause()
        let client = DeferredTranslationClient()
        let session = TranslationSession(client: client, waitForTypingPause: { try await pause.wait() },
                                         readAPIKey: { "test" })
        session.update(query: .init(text: "Hello"), language: .english)
        let first = await pause.nextPause()
        #expect(session.state == .waiting)
        #expect(await client.requests.isEmpty)
        // Even a trailing space is input and must restart the timer.
        session.update(query: .init(text: "Hello "), language: .english)
        let second = await pause.nextPause()
        await pause.finish(first)
        for _ in 0..<20 { await Task.yield() }
        #expect(session.state == .waiting)
        #expect(await client.requests.isEmpty)
        await pause.finish(second)
        #expect(await client.nextRequest() == "Hello ")
        session.update(query: .init(text: "Hello "), language: .english)
        #expect(session.state == .loading)
        await receiveAnswer(session, client: client, text: "Hello ")
        #expect(await client.requests == ["Hello "])
        #expect(session.state.answer == "translated")
    }

    @Test func leavingTranslationOrClearingInputCancelsPendingRequests() async {
        let pause = ControlledTypingPause()
        let client = DeferredTranslationClient()
        let session = TranslationSession(client: client, waitForTypingPause: { try await pause.wait() },
                                         readAPIKey: { "test" })
        for nextQuery: TranslationQuery? in [nil, .init(text: " \n ")] {
            session.update(query: .init(text: "Hello"), language: .english)
            let pending = await pause.nextPause()
            session.update(query: nextQuery, language: .english)
            await pause.finish(pending)
            for _ in 0..<20 { await Task.yield() }
            #expect(session.state == .ready)
            #expect(await client.requests.isEmpty)
        }
        session.update(query: .init(text: "Hello"), language: .english)
        let pending = await pause.nextPause()
        session.cancel()
        await pause.finish(pending)
        for _ in 0..<20 { await Task.yield() }
        #expect(session.state == .ready)
        #expect(await client.requests.isEmpty)
    }

    @Test func markedTextIsNotSentUntilCompositionFinishes() async {
        let pause = ControlledTypingPause()
        let client = DeferredTranslationClient()
        let session = TranslationSession(client: client, waitForTypingPause: { try await pause.wait() },
                                         readAPIKey: { "test" })
        session.update(query: .init(text: "你好"), language: .english, isComposing: true)
        session.submit()
        #expect(session.state == .ready)
        #expect(await client.requests.isEmpty)
        session.update(query: .init(text: "你好"), language: .english, isComposing: false)
        let pending = await pause.nextPause()
        #expect(session.state == .waiting)
        await pause.finish(pending)
        #expect(await client.nextRequest() == "你好")
        await receiveAnswer(session, client: client, text: "你好")
    }

    @Test func infersOnlyLatestCommittedTextAfterThePauseEvenWithoutAnAPIKey() async {
        let pause = ControlledTypingPause()
        var inferred: [String] = []
        let session = TranslationSession(inferSourceLanguage: { text in
            inferred.append(text)
            return .init(code: "en")
        }, waitForTypingPause: { try await pause.wait() }, readAPIKey: { nil })
        session.update(query: .init(text: "unfinished"), language: .japanese, isComposing: true)
        #expect(inferred.isEmpty && session.sourceLanguage == nil)
        session.update(query: .init(text: "old input"), language: .japanese)
        let oldPause = await pause.nextPause()
        session.update(query: .init(text: "latest input"), language: .japanese)
        let latestPause = await pause.nextPause()
        await pause.finish(oldPause)
        for _ in 0..<20 { await Task.yield() }
        #expect(inferred.isEmpty && session.sourceLanguage == nil)
        await withCheckedContinuation { done in
            session.onChange = { if session.state == .needsAPIKey { done.resume() } }
            Task { await pause.finish(latestPause) }
        }
        session.onChange = nil
        #expect(inferred == ["latest input"])
        #expect(session.sourceLanguage?.code == "en")
        session.update(query: nil, language: .japanese)
        #expect(session.sourceLanguage == nil)
    }

    @Test func deepSeekSourceReplacesTheLocalPreviewWithoutAnotherRequest() async {
        let client = DeferredTranslationClient()
        let session = TranslationSession(client: client, inferSourceLanguage: { _ in .init(code: "en") },
                                         readAPIKey: { "test" })
        session.update(query: .init(text: "Bonjour"), language: .japanese)
        session.submit()
        #expect(await client.nextRequest() == "Bonjour")
        #expect(session.sourceLanguage == .init(code: "en"))
        await withCheckedContinuation { done in
            session.onChange = { if session.state.answer != nil { done.resume() } }
            Task { await client.complete("Bonjour", answer: "こんにちは", sourceLanguage: .init(code: "fr", origin: .deepSeek)) }
        }
        session.onChange = nil
        #expect(session.sourceLanguage == .init(code: "fr", origin: .deepSeek))
        #expect(session.state.answer == "こんにちは")
        #expect(await client.requests == ["Bonjour"])
        session.cancel()
        #expect(session.sourceLanguage == nil)
    }

    private func receiveAnswer(_ session: TranslationSession, client: DeferredTranslationClient, text: String) async {
        await withCheckedContinuation { done in
            session.onChange = {
                if session.state.answer != nil { done.resume() }
            }
            Task { await client.complete(text, answer: "translated") }
        }
        session.onChange = nil
    }
}
