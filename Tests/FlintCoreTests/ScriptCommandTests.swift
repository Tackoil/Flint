import XCTest
@testable import FlintCore

final class ScriptCommandTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/Flint Scripts/hello.sh")
    private func source(_ extra: String = "", body: String = "echo hello", mode: String = "fullOutput") -> String {
        "#!/bin/bash\n# @raycast.schemaVersion 1\n# @raycast.title Hello\n# @raycast.mode \(mode)\n\(extra)\n\(body)\n"
    }

    func testRaycastMetadataAndWorkingDirectory() throws {
        let command = try ScriptCommand.parse(source("# @raycast.packageName Tools\n# @raycast.description Test script\n# @raycast.currentDirectoryPath ../Projects\n# @raycast.needsConfirmation true"), url: url)
        XCTAssertEqual(command.name, "Hello")
        XCTAssertEqual(command.packageName, "Tools")
        XCTAssertEqual(command.description, "Test script")
        XCTAssertEqual(command.currentDirectory.path, "/tmp/Projects")
        XCTAssertEqual(command.interpreter, ["/bin/bash"])
        XCTAssertTrue(command.needsConfirmation)
        XCTAssertEqual(LauncherItem.script(command).kind, "Script")
        XCTAssertEqual(ApplicationSearch.filter([.script(command)], query: "hel"), [.script(command)])
    }

    func testFlintAndSlashCommentMetadata() throws {
        let text = source().replacingOccurrences(of: "# @raycast", with: "// @flint")
        XCTAssertEqual(try ScriptCommand.parse(text, url: url).name, "Hello")
    }

    func testArgumentsPreserveLiteralValuesAndEncodeWhenRequested() throws {
        let command = try ScriptCommand.parse(source("""
        # @raycast.argument1 {"type":"password","placeholder":"Secret"}
        # @raycast.argument2 {"type":"text","placeholder":"Query","percentEncoded":true}
        # @raycast.argument3 {"type":"dropdown","placeholder":"Choice","optional":true,"data":[{"title":"One","value":"1"}]}
        """), url: url)
        XCTAssertEqual(command.arguments[0].type, .password)
        XCTAssertEqual(try command.preparedArguments(["$(touch nope); '你好'", "a & b", ""]), ["$(touch nope); '你好'", "a%20%26%20b", ""])
        XCTAssertThrowsError(try command.preparedArguments(["", "query", ""]))
        XCTAssertThrowsError(try command.preparedArguments([]))
    }

    func testInvalidMetadataIsReported() {
        for text in [source(mode: "inline"), source().replacingOccurrences(of: "schemaVersion 1", with: "schemaVersion 2"),
                     source("# @raycast.argument2 {}"), source("# @raycast.argument4 {}"), source("# @raycast.argument1 not-json"),
                     source("# @raycast.argument1 {\"type\":\"dropdown\",\"placeholder\":\"Pick\"}"), "echo nope"] {
            XCTAssertThrowsError(try ScriptCommand.parse(text, url: url))
        }
    }

    func testStorePersistenceAndDiscovery() throws {
        let suite = "ScriptTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try source().write(to: directory.appendingPathComponent("hello.sh"), atomically: true, encoding: .utf8)
        try source().write(to: directory.appendingPathComponent("skip.template.sh"), atomically: true, encoding: .utf8)
        try "bad".write(to: directory.appendingPathComponent("bad.py"), atomically: true, encoding: .utf8)
        let hidden = directory.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try source().write(to: hidden.appendingPathComponent("hidden.sh"), atomically: true, encoding: .utf8)
        let store = ScriptCommandStore(defaults: defaults)
        store.add(directory)
        store.add(directory)
        XCTAssertEqual(ScriptCommandStore(defaults: defaults).directories, [URL(fileURLWithPath: directory.path, isDirectory: true)])
        let result = ScriptDiscovery.scan(directories: store.directories + [directory])
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(result.issues.count, 1)
        store.remove(directory)
        XCTAssertTrue(store.directories.isEmpty)
        XCTAssertEqual(ScriptDiscovery.scan(directories: [directory.appendingPathComponent("missing")]).issues.count, 1)
    }

    func testRunnerUsesInterpreterLiteralArgumentsAndWorkingDirectory() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("not executable.sh")
        try source("# @raycast.argument1 {\"type\":\"text\",\"placeholder\":\"Value\"}", body: "printf '%s\\n' \"$1\"; pwd; printf 'stderr' >&2; exit 7")
            .write(to: script, atomically: true, encoding: .utf8)
        let value = "$(touch should-not-exist); '你好'"
        let result = try await ScriptRunner().run(ScriptCommand.load(from: script), values: [value])
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains(value))
        XCTAssertTrue(result.output.contains(directory.path))
        XCTAssertTrue(result.output.contains("stderr"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("should-not-exist").path))
    }

    func testRunnerCancellationAndTimeout() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("wait.sh")
        try source(body: "exec /bin/sleep 30").write(to: script, atomically: true, encoding: .utf8)
        let command = try ScriptCommand.load(from: script)
        let timedOut = try await ScriptRunner().run(command, values: [], timeout: 0.1)
        XCTAssertTrue(timedOut.timedOut)
        XCTAssertFalse(timedOut.succeeded)
        let runner = ScriptRunner()
        let task = Task { try await runner.run(command, values: []) }
        try await Task.sleep(for: .milliseconds(100))
        runner.cancel()
        let cancelled = try await task.value
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertFalse(cancelled.succeeded)
    }

    func testLargeOutputDoesNotDeadlockAndIsBounded() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("output.sh")
        try source(body: "/usr/bin/head -c 1200000 /dev/zero | /usr/bin/tr '\\0' x")
            .write(to: script, atomically: true, encoding: .utf8)
        let result = try await ScriptRunner().run(ScriptCommand.load(from: script), values: [])
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.hasSuffix("[Output truncated at 1 MB]"))
        XCTAssertLessThan(result.output.utf8.count, 1_049_000)
    }

    func testTemplateCanBeDiscovered() throws {
        let command = try ScriptCommand.parse(ScriptCommandStore.template, url: url)
        XCTAssertEqual(command.name, "Hello World")
        XCTAssertTrue(command.arguments[0].optional)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Flint Script Tests \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
