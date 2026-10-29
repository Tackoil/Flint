import Foundation

enum ApplicationSearch {
    static func filter(_ applications: [ApplicationRecord], query: String) -> [ApplicationRecord] {
        ranked(applications, query: query, name: \.name)
    }

    static func filter(_ items: [LauncherItem], query: String) -> [LauncherItem] {
        ranked(items, query: query, name: \.name)
    }

    private static func ranked<Item>(_ items: [Item], query: String, name: (Item) -> String) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        guard !query.isEmpty else { return items }

        return items.compactMap { item -> (Item, Int)? in
            let searchableName = name(item).folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current
            )
            guard let score = score(name: searchableName, query: query) else { return nil }
            return (item, score)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return name(lhs.0).localizedStandardCompare(name(rhs.0)) == .orderedAscending
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
