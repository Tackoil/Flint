import AppKit

@MainActor
struct SystemActionExecutor {
    var listVolumes: @MainActor () throws -> [URL] = ejectableVolumes
    var ejectVolume: @MainActor (URL) async throws -> Void = eject
    var emptyTrash: @MainActor () async throws -> Void = { try await emptyFinderTrash() }
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

    static func emptyFinderTrash(runScript: @MainActor (String) async throws -> Void = runAppleScript) async throws {
        do {
            try await runScript(confirmedEmptyTrashScript)
        } catch {
            let message = error.localizedDescription
            // osascript ends its diagnostic with the numeric AppleScript error code.
            guard message.hasSuffix("(-1743)") else { throw error }
            throw ActionError(message: "Allow Flint to control Finder in System Settings → Privacy & Security → Automation, then try again.")
        }
    }

    // The launcher has already confirmed deletion. Avoid a second, potentially
    // background Finder warning, and restore the user's preference on every path.
    static let confirmedEmptyTrashScript = """
    tell application id "com.apple.finder"
        if (count of items of trash) is 0 then return
        set originalWarning to warns before emptying of trash
        try
            set warns before emptying of trash to false
            with timeout of 3600 seconds
                empty trash
            end timeout
        on error failureMessage number failureNumber
            set warns before emptying of trash to originalWarning
            error failureMessage number failureNumber
        end try
        set warns before emptying of trash to originalWarning
        repeat 300 times
            if (count of items of trash) is 0 then return
            delay 0.1
        end repeat
        error "Finder hasn’t finished emptying the Trash. Check the Trash in Finder before trying again."
    end tell
    """

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

    static func runAppleScript(_ script: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
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
