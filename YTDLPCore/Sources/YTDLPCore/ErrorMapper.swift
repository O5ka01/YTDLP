import Foundation

/// Reduces yt-dlp's developer-facing stderr to one sentence a person can act on.
/// The raw text is still shown behind the UI's "Details" disclosure.
public enum ErrorMapper {
    private static let rules: [(needles: [String], message: String)] = [
        (["sign in to confirm your age", "members-only", "private video", "sign in if you"],
         "This video needs a login — try turning on Use Safari cookies."),
        (["video unavailable", "has been removed", "no longer available"],
         "This video isn't available."),
        (["unsupported url"],
         "yt-dlp doesn't recognise this site."),
        (["ffmpeg not found", "ffmpeg is not installed"],
         "The bundled ffmpeg is missing — reinstall the app."),
    ]

    public static func message(forStderr stderr: String) -> String {
        let haystack = stderr.lowercased()
        for rule in rules where rule.needles.contains(where: haystack.contains) {
            return rule.message
        }

        let firstLine = stderr
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        return firstLine ?? "The download failed for an unknown reason."
    }
}
