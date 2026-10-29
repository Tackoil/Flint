import Foundation
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
        let client = DeepSeekTranslationClient { request in
            #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.timeoutInterval == 60)
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(body["model"] as? String == "deepseek-flash")
            #expect(body["stream"] as? Bool == false)
            #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
            let messages = try #require(body["messages"] as? [[String: String]])
            #expect(messages[0]["content"]?.contains("Japanese") == true)
            #expect(messages[1] == ["role": "user", "content": "Hello\nworld"])
            return response(#"{"choices":[{"message":{"content":"こんにちは\n世界"},"finish_reason":"stop"}]}"#)
        }
        let result = try await client.translate("Hello\nworld", to: .japanese, apiKey: " test-key ")
        #expect(result == "こんにちは\n世界")
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
}

private func response(_ body: String, status: Int = 200) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://api.deepseek.com/chat/completions")!,
                                    statusCode: status, httpVersion: nil, headerFields: nil)!)
}

private actor DeferredTranslationClient: TranslationServing {
    private(set) var requests: [String] = []
    private var pending: [String: CheckedContinuation<String, any Error>] = [:]
    private var started: [String] = []
    private var observer: CheckedContinuation<String, Never>?

    func translate(_ text: String, to language: TranslationLanguage, apiKey: String) async throws -> String {
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

    func complete(_ text: String, answer: String) {
        pending.removeValue(forKey: text)?.resume(returning: answer)
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
        let session = TranslationSession(client: client, readAPIKey: { "test" })
        session.update(query: .init(text: "old"), language: .english)
        session.submit()
        #expect(session.state == .loading)
        #expect(await client.nextRequest() == "old")
        session.update(query: .init(text: "new"), language: .english)
        #expect(session.state == .waiting)
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
        session.onChange = nil
        session.cancel()
        #expect(session.state == .ready)
        #expect(session.state.answer == nil)
    }

    @Test func targetChangesInvalidateTheAnswer() async {
        let client = DeepSeekTranslationClient { _ in response(#"{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}"#) }
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
