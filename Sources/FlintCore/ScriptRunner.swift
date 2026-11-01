import Foundation
import Darwin

struct ScriptRunResult: Sendable {
    let output: String
    let exitCode: Int32
    let cancelled: Bool
    let timedOut: Bool
    var succeeded: Bool { exitCode == 0 && !cancelled && !timedOut }
}

/// One runner per invocation. The lock synchronizes cancellation with process startup.
final class ScriptRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private let outputLimit = 1_048_576

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        stop(running)
    }

    func run(_ command: ScriptCommand, values: [String], timeout: TimeInterval = 60) async throws -> ScriptRunResult {
        let arguments = try command.preparedArguments(values)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { [self] in
                try execute(command, arguments: arguments, timeout: timeout)
            }.value
        } onCancel: { self.cancel() }
    }

    private func execute(_ command: ScriptCommand, arguments: [String], timeout: TimeInterval) throws -> ScriptRunResult {
        let task = Process()
        guard let interpreter = command.interpreter.first else { throw ScriptCommandError.invalid("Missing script interpreter.") }
        task.executableURL = URL(fileURLWithPath: interpreter)
        task.arguments = Array(command.interpreter.dropFirst()) + [command.url.path] + arguments
        task.currentDirectoryURL = command.currentDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        task.environment = environment
        task.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        let reader = pipe.fileHandleForReading
        defer { try? reader.close(); try? pipe.fileHandleForWriting.close() }
        _ = fcntl(reader.fileDescriptor, F_SETFL, O_NONBLOCK)
        try launch(task)
        try? pipe.fileHandleForWriting.close()
        let captured = capture(task, descriptor: reader.fileDescriptor, timeout: timeout)
        task.waitUntilExit()
        lock.lock()
        process = nil
        let wasCancelled = cancelled
        lock.unlock()
        return ScriptRunResult(output: captured.output, exitCode: task.terminationStatus,
                               cancelled: wasCancelled, timedOut: captured.timedOut)
    }

    private func launch(_ task: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try task.run()
        process = task
    }

    private func capture(_ task: Process, descriptor: Int32, timeout: TimeInterval) -> (output: String, timedOut: Bool) {
        var data = Data()
        var truncated = false
        var timedOut = false
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var exitDeadline: TimeInterval?
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let remaining = max(0, outputLimit - data.count)
                data.append(contentsOf: buffer.prefix(min(count, remaining)))
                truncated = truncated || count > remaining
            }
            if !timedOut && ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = true
                stop(task)
            }
            if finishedDraining(task, count: count, exitDeadline: &exitDeadline) { break }
            if count <= 0 { Thread.sleep(forTimeInterval: 0.01) }
        }
        let suffix = truncated ? "\n[Output truncated at 1 MB]" : ""
        return (String(decoding: data, as: UTF8.self) + suffix, timedOut)
    }

    private func finishedDraining(_ task: Process, count: Int, exitDeadline: inout TimeInterval?) -> Bool {
        guard !task.isRunning else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = exitDeadline ?? now + 0.05
        exitDeadline = deadline
        return count <= 0 || now >= deadline
    }

    private func stop(_ task: Process?) {
        guard let task, task.isRunning else { return }
        let pid = task.processIdentifier
        let ownsGroup = getpgid(pid) == pid
        if ownsGroup { killpg(pid, SIGTERM) } else { task.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if ownsGroup { killpg(pid, SIGKILL) }
            else if task.isRunning { kill(pid, SIGKILL) }
        }
    }
}
