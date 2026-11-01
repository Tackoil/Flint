import Foundation

struct ScriptCommand: Hashable, Identifiable, Sendable {
    enum Mode: String, Sendable { case silent, compact, fullOutput }
    struct Argument: Decodable, Hashable, Sendable {
        enum Kind: String, Decodable, Sendable { case text, password, dropdown }
        struct Option: Decodable, Hashable, Sendable { let title: String; let value: String }
        let type: Kind
        let placeholder: String
        var optional: Bool = false
        var percentEncoded: Bool = false
        var data: [Option] = []

        private enum CodingKeys: String, CodingKey { case type, placeholder, optional, percentEncoded, data }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(Kind.self, forKey: .type)
            placeholder = try values.decode(String.self, forKey: .placeholder)
            optional = try values.decodeIfPresent(Bool.self, forKey: .optional) ?? false
            percentEncoded = try values.decodeIfPresent(Bool.self, forKey: .percentEncoded) ?? false
            data = try values.decodeIfPresent([Option].self, forKey: .data) ?? []
            guard !placeholder.isEmpty, type != .dropdown || !data.isEmpty else {
                throw ScriptCommandError.invalid("Arguments need a placeholder; dropdowns also need options.")
            }
        }
    }

    let url: URL
    let name: String
    let mode: Mode
    let packageName: String
    let description: String
    let needsConfirmation: Bool
    let currentDirectory: URL
    let interpreter: [String]
    let arguments: [Argument]
    var id: String { url.path }

    static func load(from url: URL) throws -> ScriptCommand {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 65_536) ?? Data()
        guard let source = String(data: data, encoding: .utf8) else {
            throw ScriptCommandError.invalid("Use UTF-8 text for script commands.")
        }
        return try parse(source, url: url)
    }

    static func parse(_ source: String, url: URL) throws -> ScriptCommand {
        let lines = source.components(separatedBy: .newlines)
        guard let first = lines.first, first.hasPrefix("#!/") else {
            throw ScriptCommandError.invalid("Add a shebang, such as #!/bin/bash, on the first line.")
        }
        let metadata = metadata(in: lines)
        guard metadata["schemaVersion"] == "1", let title = metadata["title"], !title.isEmpty else {
            throw ScriptCommandError.invalid("Add schemaVersion 1 and a title using @raycast or @flint comments.")
        }
        guard let mode = metadata["mode"].flatMap(Mode.init) else {
            throw ScriptCommandError.invalid("Supported modes are silent, compact, and fullOutput. Inline refresh is not supported.")
        }
        let directory = url.deletingLastPathComponent()
        let workingPath = metadata["currentDirectoryPath"].map { ($0 as NSString).expandingTildeInPath }
        return ScriptCommand(url: url, name: title, mode: mode,
                             packageName: metadata["packageName"] ?? directory.lastPathComponent,
                             description: metadata["description"] ?? "",
                             needsConfirmation: metadata["needsConfirmation"] == "true",
                             currentDirectory: workingPath.map { URL(fileURLWithPath: $0, relativeTo: directory).standardizedFileURL } ?? directory,
                             interpreter: first.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init),
                             arguments: try parseArguments(metadata))
    }

    private static func metadata(in lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines.prefix(128) {
            let comment = line.trimmingCharacters(in: .whitespaces)
            guard comment.hasPrefix("#") || comment.hasPrefix("//") else { continue }
            let text = comment.drop(while: { $0 == "#" || $0 == "/" || $0.isWhitespace })
            guard text.hasPrefix("@raycast.") || text.hasPrefix("@flint."),
                  let space = text.firstIndex(where: \.isWhitespace), let dot = text.firstIndex(of: ".") else { continue }
            result[String(text[text.index(after: dot)..<space])] = text[space...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func parseArguments(_ metadata: [String: String]) throws -> [Argument] {
        guard metadata["argument4"] == nil else {
            throw ScriptCommandError.invalid("Use no more than three script arguments.")
        }
        var arguments: [Argument] = []
        for index in 1...3 {
            guard let value = metadata["argument\(index)"] else { continue }
            guard arguments.count == index - 1 else {
                throw ScriptCommandError.invalid("Number arguments consecutively, starting at argument1.")
            }
            do { arguments.append(try JSONDecoder().decode(Argument.self, from: Data(value.utf8))) }
            catch { throw ScriptCommandError.invalid("Check the JSON for argument\(index): \(error.localizedDescription)") }
        }
        return arguments
    }

    func preparedArguments(_ values: [String]) throws -> [String] {
        guard values.count == arguments.count else { throw ScriptCommandError.invalid("Complete the script arguments.") }
        return try zip(arguments, values).map { argument, value in
            guard argument.optional || !value.isEmpty else {
                throw ScriptCommandError.invalid("Enter a value for \(argument.placeholder).")
            }
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            return argument.percentEncoded ? value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" : value
        }
    }
}

enum ScriptCommandError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
