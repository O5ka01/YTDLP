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

            let stdoutBuffer = LineBuffer()
            let stderrBuffer = LineBuffer()

            forward(stdout, buffer: stdoutBuffer, as: ProcessEvent.stdout, to: continuation)
            forward(stderr, buffer: stderrBuffer, as: ProcessEvent.stderr, to: continuation)

            /// Reads whatever is left in a pipe until EOF. Only safe to call once the
            /// child has actually exited and closed its end of the pipe — otherwise
            /// `availableData` can block waiting for a write end that is still open.
            let drainRemaining: @Sendable (Pipe, LineBuffer, @escaping @Sendable (String) -> ProcessEvent) -> Void = { pipe, buffer, makeEvent in
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    for line in buffer.append(data) {
                        continuation.yield(makeEvent(line))
                    }
                }
            }

            /// Emits any trailing bytes that never got a terminating newline.
            let flushTrailing: @Sendable (LineBuffer, @escaping @Sendable (String) -> ProcessEvent) -> Void = { buffer, makeEvent in
                if let text = buffer.flushRemainder() {
                    continuation.yield(makeEvent(text))
                }
            }

            /// Tears down both pipes' readability handlers and flushes buffered text.
            ///
            /// - Parameter draining: `true` once the child has exited, so `availableData`
            ///   is safe to loop to EOF (the write end is closed). Pass `false` on the
            ///   launch-failure path, where the process never ran: the parent still
            ///   holds the pipes' write ends open, so a read there would block forever.
            ///   In that case no data can possibly exist to drain, so only the
            ///   (necessarily empty) buffers are flushed.
            let finishStreams: @Sendable (Bool) -> Void = { draining in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil

                if draining {
                    drainRemaining(stdout, stdoutBuffer, ProcessEvent.stdout)
                    drainRemaining(stderr, stderrBuffer, ProcessEvent.stderr)
                }

                flushTrailing(stdoutBuffer, ProcessEvent.stdout)
                flushTrailing(stderrBuffer, ProcessEvent.stderr)
            }

            process.terminationHandler = { finished in
                finishStreams(true)
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
                finishStreams(false)
                continuation.yield(.stderr("ERROR: could not launch \(executable): \(error.localizedDescription)"))
                continuation.yield(.exit(code: -1))
                continuation.finish()
            }
        }
    }

    /// yt-dlp emits progress with `--newline`, so splitting on newlines is safe.
    /// A trailing partial line is buffered until its newline arrives, or until
    /// `finishStreams` flushes it explicitly.
    private func forward(
        _ pipe: Pipe,
        buffer: LineBuffer,
        as makeEvent: @escaping @Sendable (String) -> ProcessEvent,
        to continuation: AsyncStream<ProcessEvent>.Continuation
    ) {
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

    /// Returns any bytes that never got a trailing newline, clearing the buffer.
    func flushRemainder() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let text = String(data: pending, encoding: .utf8)?.trimmingCharacters(in: .whitespaces)
        pending.removeAll()
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
