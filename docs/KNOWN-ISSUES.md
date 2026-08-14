# Known issues

Findings raised during review that were deliberately not fixed. All were triaged in the
final whole-branch review as "ship as-is" for a personal-use app. None is a crash, data-loss,
or security issue.

## Behaviour

- **A re-copied URL won't re-fill the field.** Clipboard adoption compares URL *content*, so
  after a download resets the field, copying the same URL again does not re-fill it. Using
  `NSPasteboard.changeCount` would fix that but would also re-fill a field you deliberately
  cleared — a real tradeoff, not a clear win. Left as-is on purpose.

- **Playlists always download at "Best".** `MediaProbe` passes `--flat-playlist`, so a playlist
  probe returns no formats and the quality menu stays hidden.

- **Re-downloading a playlist can silently do nothing.** `--download-archive` records what was
  already fetched, so re-running a playlist after deleting the files exits successfully having
  downloaded nothing, and reports "Done". There is no UI to clear the archive; delete
  `~/Library/Application Support/YTDLP/archive.txt` by hand.

- **A missing deno shows in red like a fatal error.** deno is optional — only sites whose
  extractor runs JavaScript need it — but `SettingsView.pathRow` has one style for "not found",
  so its row reads as urgently as a missing ffmpeg. The caption underneath explains the real
  consequence.

- **Tool paths are resolved once at launch.** Running `brew uninstall yt-dlp` while the app is
  open produces a raw launch error rather than the friendly install message. Relaunch to recover.

- **Install hints assume Homebrew exists.** Every "not found" message says `brew install …`,
  which dead-ends for someone who doesn't have Homebrew at all.

- **A redundant probe restart in one narrow window.** If you type a URL during the brief moment
  between the toolchain being resolved and `prepare()` returning, the probe restarts once
  (~400 ms). Cosmetic; the data is correct.

## Divergences from the design spec

Recorded deliberately, with reasons:

- **No notification action buttons.** "Reveal in Finder" / "Play" on the notification itself would
  need a `UNUserNotificationCenterDelegate` plus the final filename, which yt-dlp only reports in
  its `[download] Destination:` line. The queue row's own buttons cover the same need.
- **No "Play" button on a finished row**, for the same filename reason.
- **The Download button never becomes Cancel.** Cancellation lives on each queue row instead,
  which suits a multi-job queue better than a single global button.
- **Format labels show filesize, not codec** ("1080p · 91 MB"). The codec is a global preference,
  so repeating it per row would be noise.

## Code cleanliness

- Three separately-worded "tool not found" strings: `BinaryManager.BinaryError`, a copy in
  `DownloadQueue.start`, and one in `SettingsView.pathRow`. The command is identical in all three;
  the phrasing could drift. One shared helper would fix it.
- `ErrorMapper` has no rule for HTTP 404-style failures, so they surface as the raw yt-dlp line.
  Now visible via the Details disclosure, so it matters less than it did.
- `MediaInfo.title` is non-optional while `PlaylistEntry.title` was made optional for exactly the
  null-title failure mode. A null top-level title would fail the whole probe. Much rarer.
- `ProgressParser`'s retry check uses a broad `contains("Retrying")` before the stage-prefix loop.
  Safe against real yt-dlp output, but correct by data rather than by construction.
- `SystemProcessRunner` has a narrow race where a readability handler can fire after
  `continuation.finish()`, dropping the final stderr line. Lock-protected, so no corruption.
- A few brief-mandated tests are weaker than ideal (`ProcessRunnerTests` asserts only synthesized
  `Equatable`; `defaultOptionsAreVideoBestQuality` checks 4 of 11 properties).
