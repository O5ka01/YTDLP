import Foundation

/// One line of output from a child process, or its termination.
public enum ProcessEvent: Equatable, Sendable {
    case stdout(String)
    case stderr(String)
    case exit(code: Int32)
}

/// Spawns a child process and streams its output.
///
/// The only production conformance is `SystemProcessRunner` in the app target.
/// Cancelling the consuming `Task` must terminate the child with `SIGINT` so that
/// yt-dlp removes its own `.part` files.
public protocol ProcessRunner: Sendable {
    func run(executable: String, arguments: [String]) -> AsyncStream<ProcessEvent>
}
