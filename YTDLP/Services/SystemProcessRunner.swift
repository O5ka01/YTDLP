import Foundation
import YTDLPCore

/// Runs a real child process and streams its output line by line.
///
/// Cancelling the `Task` that consumes the stream terminates the child with
/// `SIGINT`, giving yt-dlp a chance to clean up partial fragments. If it has not
/// exited after 3 seconds, it is killed.
struct SystemProcessRunner: ProcessRunner {
    func run(executable: String, arguments: [String]) -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            forward(stdout, as: ProcessEvent.stdout, to: continuation)
            forward(stderr, as: ProcessEvent.stderr, to: continuation)

            process.terminationHandler = { finished in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.yield(.exit(code: finished.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { reason in
                guard case .cancelled = reason, process.isRunning else { return }
                process.interrupt()
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if process.isRunning { process.terminate() }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.stderr("ERROR: could not launch \(executable): \(error.localizedDescription)"))
                continuation.yield(.exit(code: -1))
                continuation.finish()
            }
        }
    }

    /// yt-dlp emits progress with `--newline`, so splitting on newlines is safe.
    /// A trailing partial line is buffered until its newline arrives.
    private func forward(
        _ pipe: Pipe,
        as makeEvent: @escaping @Sendable (String) -> ProcessEvent,
        to continuation: AsyncStream<ProcessEvent>.Continuation
    ) {
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in buffer.append(data) {
                continuation.yield(makeEvent(line))
            }
        }
    }
}

/// Accumulates bytes and hands back only whole lines.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return lines
    }
}
