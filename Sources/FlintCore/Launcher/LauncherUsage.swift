import Foundation

final class LauncherUsage {
    private static let countsKey = "launcher.usageCounts"
    private let defaults: UserDefaults?
    private(set) var counts: [String: Int]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        counts = defaults?.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:]
    }

    func recordUse(of item: LauncherItem) {
        let count = max(0, counts[item.usageID, default: 0])
        guard count < Int.max else { return }
        counts[item.usageID] = count + 1
        defaults?.set(counts, forKey: Self.countsKey)
    }
}
