import Foundation
import Testing
@testable import FlintCore

struct ApplicationSearchTests {
    private func app(_ name: String) -> ApplicationRecord {
        ApplicationRecord(name: name, bundleIdentifier: nil, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    @Test func emptyQueryPreservesOrder() {
        let apps = [app("Safari"), app("Mail")]
        #expect(ApplicationSearch.filter(apps, query: " \n") == apps)
    }

    @Test func exactMatchRanksBeforePrefixAndSubstring() {
        let apps = [app("Super Mail"), app("MailMate"), app("Mail")]
        #expect(ApplicationSearch.filter(apps, query: "mail").map(\.name) == ["Mail", "MailMate", "Super Mail"])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        #expect(ApplicationSearch.filter([app("Café")], query: " CAFE ").count == 1)
    }

    @Test func abbreviationMatchesAcrossWords() {
        let apps = [app("Visual Studio Code"), app("Calendar")]
        #expect(ApplicationSearch.filter(apps, query: "vsc").map(\.name) == ["Visual Studio Code"])
    }

    @Test func missingOrRepeatedCharactersDoNotMatch() {
        let apps = [app("Safari")]
        #expect(ApplicationSearch.filter(apps, query: "zzz").isEmpty)
        #expect(ApplicationSearch.filter(apps, query: "safariii").isEmpty)
    }

    @Test func unicodeQueryDoesNotBreakSearch() {
        #expect(ApplicationSearch.filter([app("微信")], query: "微").count == 1)
    }
}
