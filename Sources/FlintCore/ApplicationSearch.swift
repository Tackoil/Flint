import Foundation

enum ApplicationSearch {
    static func filter(_ applications: [ApplicationRecord], query: String) -> [ApplicationRecord] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        guard !query.isEmpty else { return applications }

        return applications.compactMap { application -> (ApplicationRecord, Int)? in
            guard let score = score(name: application.searchableName, query: query) else { return nil }
            return (application, score)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }.map(\.0)
    }

    private static func score(name: String, query: String) -> Int? {
        if name == query { return 0 }
        if name.hasPrefix(query) { return 100 }
        if let range = name.range(of: query) {
            return 200 + name.distance(from: name.startIndex, to: range.lowerBound)
        }
        return subsequenceScore(name: name, query: query)
    }

    private static func subsequenceScore(name: String, query: String) -> Int? {
        var remaining = name.startIndex
        var gaps = 0
        for character in query where !character.isWhitespace {
            guard let match = name[remaining...].firstIndex(of: character) else { return nil }
            gaps += name.distance(from: remaining, to: match)
            remaining = name.index(after: match)
        }
        return 500 + gaps
    }
}
