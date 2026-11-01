import Foundation

struct ScriptDiscovery: Sendable {
    var commands: [ScriptCommand] = []
    var issues: [String] = []

    static func scan(directories: [URL]) -> ScriptDiscovery {
        var result = ScriptDiscovery()
        var seen = Set<String>()
        for directory in directories { result.scan(directory, seen: &seen) }
        result.commands.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    private mutating func scan(_ directory: URL, seen: inout Set<String>) {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            issues.append("\(directory.lastPathComponent): Folder is missing or unavailable.")
            return
        }
        guard let files = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        for case let url as URL in files {
            guard commands.count < 1_000 else { issues.append("Only the first 1,000 script commands are loaded."); break }
            loadCandidate(url, seen: &seen)
        }
    }

    private mutating func loadCandidate(_ url: URL, seen: inout Set<String>) {
        let extensions = ["sh", "bash", "zsh", "py", "rb", "js", "ts", "swift", "applescript", "scpt", "pl"]
        guard extensions.contains(url.pathExtension), !url.lastPathComponent.contains(".template."),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              seen.insert(url.resolvingSymlinksInPath().path).inserted else { return }
        do { commands.append(try ScriptCommand.load(from: url)) }
        catch { issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
    }
}

final class ScriptCommandStore {
    static let didChange = Notification.Name("FlintScriptDirectoriesDidChange")
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var directories: [URL] {
        (defaults.stringArray(forKey: "scriptDirectories") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    func add(_ directory: URL) {
        let url = normalized(directory)
        guard !directories.contains(url) else { return }
        persist(directories + [url])
    }
    func remove(_ directory: URL) { persist(directories.filter { $0 != normalized(directory) }) }
    private func normalized(_ directory: URL) -> URL {
        URL(fileURLWithPath: directory.standardizedFileURL.path, isDirectory: true)
    }
    private func persist(_ directories: [URL]) {
        defaults.set(directories.map(\.path), forKey: "scriptDirectories")
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    static let template = """
    #!/bin/bash
    # @raycast.schemaVersion 1
    # @raycast.title Hello World
    # @raycast.mode fullOutput
    # @raycast.description A first script command for Flint.
    # @raycast.argument1 {"type":"text","placeholder":"Name","optional":true}

    printf 'Hello, %s!\\n' "${1:-world}"

    """
}
