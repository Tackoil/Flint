import AppKit

@MainActor
struct SystemActionExecutor {
    var listVolumes: @MainActor () throws -> [URL] = ejectableVolumes
    var ejectVolume: @MainActor (URL) async throws -> Void = eject
    var emptyTrash: @MainActor () async throws -> Void = emptyFinderTrash
    var showDesktop: @MainActor () async throws -> Void = revealDesktop

    func perform(_ action: SystemAction) async throws {
        let operations: [SystemAction: @MainActor () async throws -> Void] = [
            .ejectAllDisks: ejectAllDisks,
            .emptyTrash: emptyTrash,
            .showDesktop: showDesktop
        ]
        guard let operation = operations[action] else {
            throw ActionError(message: "This action is unavailable.")
        }
        try await operation()
    }

    private func ejectAllDisks() async throws {
        let volumes = try listVolumes()
        var failures: [String] = []
        for volume in volumes {
            do {
                try await ejectVolume(volume)
            } catch {
                failures.append("\(volume.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else { throw ActionError(message: failures.joined(separator: "\n")) }
    }

    static func isEjectableVolume(isInternal: Bool?, isEjectable: Bool?, isRemovable: Bool?) -> Bool {
        isInternal != true && (isEjectable == true || isRemovable == true)
    }

    private static func ejectableVolumes() throws -> [URL] {
        let keys: Set<URLResourceKey> = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys)) else {
            throw ActionError(message: "Couldn’t find mounted disks. Try again.")
        }
        return try volumes.filter { volume in
            let values = try volume.resourceValues(forKeys: keys)
            return isEjectableVolume(isInternal: values.volumeIsInternal,
                                     isEjectable: values.volumeIsEjectable,
                                     isRemovable: values.volumeIsRemovable)
        }
    }

    private static func eject(_ volume: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            // Ejecting one partition may already have removed the other volumes on its disk.
            guard FileManager.default.fileExists(atPath: volume.path) else { return }
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }.value
    }

    private static func emptyFinderTrash() async throws {
        do {
            try await runProcess(at: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: [
                "-e", "tell application id \"com.apple.finder\" to empty trash"
            ])
        } catch {
            guard error.localizedDescription.contains("-1743") else { throw error }
            throw ActionError(message: "Allow Flint to control Finder in System Settings → Privacy & Security → Automation, then try again.")
        }
    }

    private static func revealDesktop() async throws {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher") else {
            throw ActionError(message: "Mission Control is unavailable on this Mac.")
        }
        // Mission Control's desktop mode avoids simulating the user's configurable keyboard shortcut.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["1"]
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
    }

    private static func runProcess(at executable: URL, arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw ActionError(message: message.isEmpty ? "The action couldn’t be completed. Try again." : message)
            }
        }.value
    }
}

private struct ActionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
