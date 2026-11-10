import Foundation

enum ApplicationSearch {
    static func filter(_ applications: [ApplicationRecord], query: String) -> [ApplicationRecord] {
        ranked(applications, query: query, name: \.name, uses: { _ in 0 })
    }

    static func filter(_ items: [LauncherItem], query: String, usageCounts: [String: Int] = [:]) -> [LauncherItem] {
        ranked(items, query: query, name: \.name, uses: { usageCounts[$0.usageID, default: 0] })
    }

    private static func ranked<Item>(_ items: [Item], query: String, name: (Item) -> String,
                                     uses: (Item) -> Int) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        guard !query.isEmpty else { return items }

        typealias Rank = (matchTier: Int, negativeUses: Int, distance: Int)
        return items.compactMap { item -> (item: Item, name: String, rank: Rank)? in
            let displayName = name(item)
            let searchableName = displayName.folding(
                options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current
            )
            guard let score = score(name: searchableName, query: query) else { return nil }
            return (item, displayName, (score.tier, -max(0, uses(item)), score.distance))
        }.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }.map(\.item)
    }

    private static func score(name: String, query: String) -> (tier: Int, distance: Int)? {
        if name == query { return (0, 0) }
        if name.hasPrefix(query) { return (1, 0) }
        if let range = name.range(of: query) {
            return (2, name.distance(from: name.startIndex, to: range.lowerBound))
        }
        return subsequenceDistance(name: name, query: query).map { (3, $0) }
    }

    private static func subsequenceDistance(name: String, query: String) -> Int? {
        var remaining = name.startIndex
        var gaps = 0
        for character in query where !character.isWhitespace {
            guard let match = name[remaining...].firstIndex(of: character) else { return nil }
            gaps += name.distance(from: remaining, to: match)
            remaining = name.index(after: match)
        }
        return gaps
    }
}
