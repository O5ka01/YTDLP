import Foundation
import YTDLPCore

@Observable
final class DownloadJob: Identifiable {
    let id = UUID()
    let title: String
    let url: String

    enum State: Equatable {
        case waiting
        case downloading(percent: Double, speed: String, eta: String)
        case processing(String)
        case retrying
        case finished
        case failed(message: String, details: String)
    }

    var state: State = .waiting

    init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// Runs downloads one at a time and publishes their progress.
///
/// Serial by design: yt-dlp already parallelises within a download via `-N`, so
/// running several at once mostly competes for the same bandwidth.
///
/// Marked `@MainActor`, for the same reason as `BinaryManager`: this is an
/// `@Observable` singleton (`static let shared`) with mutable state
/// (`jobs`, `tasks`) that SwiftUI reads directly, and it holds a `BinaryManager`
/// reference. Isolating the whole type to the main actor makes the singleton,
/// its state, and its `BinaryManager` access safe under Swift 6 strict
/// concurrency without giving up `@Observable`. `DownloadJob` is isolated the
/// same way: its `state` is only ever mutated from here, and it is captured by
/// the unstructured `Task` each job runs in, so the whole chain stays on one
/// actor with no hops needed to touch a job's state.
@MainActor
@Observable
final class DownloadQueue {
    static let shared = DownloadQueue()

    private(set) var jobs: [DownloadJob] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var runner: any ProcessRunner = SystemProcessRunner()
    var binaries: BinaryManager = .shared
    /// Called on the main actor when a job finishes successfully.
    var onFinished: ((DownloadJob) -> Void)?

    @discardableResult
    func start(url: String, options: DownloadOptions, title: String) -> DownloadJob {
        let job = DownloadJob(title: title, url: url)

        // yt-dlp hands clipping entirely to ffmpeg once `--download-sections` is
        // set: it prints ffmpeg's banner instead of any `dl:` progress lines, so
        // `ProgressParser` never sees anything to report for a clipped job. Left
        // at `.waiting`, the UI would look hung for the whole download. Start it
        // in an indeterminate "Clipping…" state instead so it visibly shows
        // activity right away.
        if options.clip != nil {
            job.state = .processing("Clipping…")
        }
        jobs.append(job)

        guard let executable = binaries.ytDlpPath else {
            job.state = .failed(
                message: "yt-dlp wasn't found. Install it with:  brew install yt-dlp",
                details: ""
            )
            return job
        }

        let resolved = OptionResolver.resolve(options)
        let arguments = ArgumentBuilder.argv(url: url, options: resolved)

        tasks[job.id] = Task { [weak self] in
            await self?.execute(job: job, executable: executable, arguments: arguments)
        }
        return job
    }

    func cancel(_ job: DownloadJob) {
        tasks[job.id]?.cancel()
        tasks[job.id] = nil
        jobs.removeAll { $0.id == job.id }
    }

    func remove(_ job: DownloadJob) {
        tasks[job.id] = nil
        jobs.removeAll { $0.id == job.id }
    }

    private func execute(job: DownloadJob, executable: String, arguments: [String]) async {
        var stderr: [String] = []
        var exitCode: Int32?

        for await event in runner.run(executable: executable, arguments: arguments) {
            switch event {
            case .stdout(let line):
                guard let progress = ProgressParser.parse(line) else { continue }
                apply(progress, to: job)

            case .stderr(let line):
                stderr.append(line)
                if let progress = ProgressParser.parse(line) {
                    apply(progress, to: job)
                }

            case .exit(let code):
                exitCode = code
            }
        }

        tasks[job.id] = nil

        // `SystemProcessRunner` signals the child (SIGINT) when this job's Task
        // is cancelled, but its stream never yields `.exit` on that path — the
        // `for await` loop above simply ends because `AsyncStream.next()`
        // returns nil once the consuming Task is cancelled, not because
        // `continuation.finish()` was ever called. So `.exit` cannot be relied
        // on to reach a terminal state: cancellation must be checked explicitly
        // once the loop ends. `cancel(_:)` already removes the job from `jobs`,
        // which is what the UI shows, but this method must still leave `job`
        // itself in a sane, non-stale state on its own.
        if Task.isCancelled {
            return
        }

        guard let exitCode else {
            // The stream ended without an exit code and we weren't cancelled —
            // don't leave the job stuck at whatever state it last had.
            let raw = stderr.joined(separator: "\n")
            job.state = .failed(message: ErrorMapper.message(forStderr: raw), details: raw)
            return
        }

        if exitCode == 0 {
            job.state = .finished
            onFinished?(job)
        } else {
            let raw = stderr.joined(separator: "\n")
            job.state = .failed(message: ErrorMapper.message(forStderr: raw), details: raw)
        }
    }

    private func apply(_ event: ProgressEvent, to job: DownloadJob) {
        switch event {
        case .progress(let percent, let speed, let eta):
            job.state = .downloading(percent: percent, speed: speed, eta: eta)
        case .stage(let stage):
            job.state = .processing(stage.label)
        case .retrying:
            job.state = .retrying
        }
    }
}
