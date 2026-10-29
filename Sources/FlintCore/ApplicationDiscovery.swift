import Foundation

enum ApplicationDiscovery {
    static var searchDirectories: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications")
        ]
    }

    static func discover(in directories: [URL] = searchDirectories) -> [ApplicationRecord] {
        var seen = Set<String>()
        return directories.flatMap(applications).filter { app in
            seen.insert(app.bundleIdentifier ?? app.url.resolvingSymlinksInPath().path).inserted
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func applications(in directory: URL) -> [ApplicationRecord] {
        if directory.pathExtension.lowercased() == "app" {
            return application(at: directory).map { [$0] } ?? []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var apps: [ApplicationRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "app" else { continue }
            enumerator.skipDescendants()
            if let app = application(at: url) { apps.append(app) }
        }
        return apps
    }

    private static func application(at url: URL) -> ApplicationRecord? {
        guard let bundle = Bundle(url: url), bundle.executableURL != nil else { return nil }
        let metadata = bundle.localizedInfoDictionary ?? [:]
        let candidates = [
            metadata["CFBundleDisplayName"],
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName"),
            metadata["CFBundleName"],
            bundle.object(forInfoDictionaryKey: "CFBundleName")
        ]
        let name = candidates.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent
        let identifier = bundle.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        return ApplicationRecord(name: name, bundleIdentifier: identifier, url: url)
    }
}
