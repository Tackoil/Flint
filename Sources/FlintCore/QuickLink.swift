import Foundation

struct QuickLink: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var link: String
    var applicationURL: URL?

    init(id: UUID = UUID(), name: String, link: String, applicationURL: URL? = nil) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.applicationURL = applicationURL
    }

    struct Argument: Hashable, Sendable {
        let token: String
        let name: String
    }

    var arguments: [Argument] {
        guard let expression = try? NSRegularExpression(pattern: #"\{(?:argument(?: name="([^"]+)")?|([^{}]+))\}"#) else { return [] }
        let source = link as NSString
        var seen = Set<String>()
        return expression.matches(in: link, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let token = source.substring(with: match.range)
            guard seen.insert(token).inserted else { return nil }
            let nameRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            let name = nameRange.location == NSNotFound ? "Query" : source.substring(with: nameRange)
            return Argument(token: token, name: name)
        }
    }

    func validate() throws {
        guard !name.isEmpty else { throw QuickLinkError.missingName }
        guard arguments.count <= 8 else { throw QuickLinkError.tooManyArguments }
        _ = try resolvedURL(values: Dictionary(uniqueKeysWithValues: arguments.map { ($0.token, "example") }))
    }

    func resolvedURL(values: [String: String] = [:]) throws -> URL {
        var destination = link
        let isPath = destination.hasPrefix("/") || destination.hasPrefix("~/")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for argument in arguments {
            guard let value = values[argument.token], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw QuickLinkError.missingArgument(argument.name)
            }
            let replacement = isPath ? value : value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            destination = destination.replacingOccurrences(of: argument.token, with: replacement)
        }
        guard !destination.isEmpty, !destination.contains("{"), !destination.contains("}") else {
            throw QuickLinkError.invalidLink
        }
        if isPath {
            return URL(fileURLWithPath: (destination as NSString).expandingTildeInPath)
        }
        guard !destination.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: destination), let scheme = url.scheme, !scheme.isEmpty else {
            throw QuickLinkError.invalidLink
        }
        if ["http", "https"].contains(scheme.lowercased()), url.host?.isEmpty != false {
            throw QuickLinkError.invalidLink
        }
        guard !["javascript", "data"].contains(scheme.lowercased()) else { throw QuickLinkError.invalidLink }
        return url
    }
}

enum QuickLinkError: LocalizedError {
    case missingName, invalidLink, tooManyArguments, missingArgument(String), missingFile

    var errorDescription: String? {
        switch self {
        case .missingName: return "Enter a name for this quick link."
        case .invalidLink: return "Enter a complete URL, app deeplink, or absolute file path (including ~/)."
        case .tooManyArguments: return "Use no more than eight different arguments."
        case .missingArgument(let name): return "Enter a value for \(name)."
        case .missingFile: return "This file or folder no longer exists. Edit the quick link in Settings."
        }
    }
}

final class QuickLinkStore {
    static let didChange = Notification.Name("FlintQuickLinksDidChange")
    private static let key = "quickLinks"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var links: [QuickLink] {
        guard let data = defaults.data(forKey: Self.key),
              let links = try? JSONDecoder().decode([QuickLink].self, from: data) else { return [] }
        return links
    }

    func save(_ link: QuickLink) throws {
        try link.validate()
        var updated = links
        if let index = updated.firstIndex(where: { $0.id == link.id }) {
            updated[index] = link
        } else {
            updated.append(link)
        }
        try persist(updated)
    }

    func remove(id: UUID) throws { try persist(links.filter { $0.id != id }) }

    private func persist(_ links: [QuickLink]) throws {
        defaults.set(try JSONEncoder().encode(links), forKey: Self.key)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
