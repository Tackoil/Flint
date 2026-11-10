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

    @Test func frequentlyUsedResultsRiseWithinTheSameMatchTier() {
        let names = ["Mail", "Mail Archive", "Mail Work", "New Mail", "Mega Mail", "Main Trail", "Calendar"]
        let items = names.map { LauncherItem.application(app($0)) }
        let counts = [items[2].usageID: 2, items[3].usageID: 9, items[4].usageID: 12,
                      items[5].usageID: 15, items[6].usageID: 20]
        let results = ApplicationSearch.filter(items.reversed(), query: "mail", usageCounts: counts)
        #expect(results.map(\.name) == ["Mail", "Mail Work", "Mail Archive", "Mega Mail", "New Mail", "Main Trail"])
        #expect(ApplicationSearch.filter(items.reversed(), query: "mail").map(\.name) == Array(names.dropLast()))
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
