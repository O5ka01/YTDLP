# yt-dlp macOS App — Design

**Date:** 2026-08-08
**Status:** Approved design, pending implementation plan

## Goal

A personal macOS app that wraps `yt-dlp` behind a minimal SwiftUI interface. It replaces an
existing AppleScript applet (`/Users/oleheinrichs/Applications/yt-dlp/yt-dlp.app`) that shows one
`display dialog` with two buttons and dumps the user into Terminal.app.

The app is for the author's own Mac. It is not distributed, not sandboxed, and not shipped to the
Mac App Store.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| UI shape | Compact window + collapsible Options drawer | Single-video case stays two controls tall; per-download options hide until needed |
| Binaries | Bundled, with yt-dlp self-updating from Application Support | YouTube breaks yt-dlp often; a static bundled copy goes stale within weeks |
| Sandbox | Off | `--cookies-from-browser` cannot read browser cookie stores under the App Sandbox |
| Signing | Xcode free personal team, local development signing | Personal use only; no Developer ID or notarization needed until the app is shared |
| Dependencies | None (no SPM packages) | Everything needed is in SwiftUI, Foundation, and UserNotifications |

## Interface

Default state — the whole window:

```
┌────────────────────────────────────────┐
│  yt-dlp                            ⚙︎  │
│  ┌──────────────────────────────────┐  │
│  │ https://youtu.be/dQw4w9WgXcQ     │  │
│  └──────────────────────────────────┘  │
│                                        │
│   ▓▓▓▓   Never Gonna Give You Up       │
│   ▓▓▓▓   Rick Astley · 3:33            │
│                                        │
│  1080p H.264 ▾   › Options  [Download] │
└────────────────────────────────────────┘
```

Expanded drawer (per-download options, reset to defaults after each download):

```
│  ⌄ Options                             │
│    ☐ Audio only    m4a ▾               │
│    ☐ Subtitles     en ▾                │
│    ☐ Clip   [00:00] – [00:00]          │
│    ☐ Use Safari cookies                │
```

The cookies checkbox is labelled with whichever browser is selected in Settings — "Use Safari
cookies", "Use Chrome cookies", and so on.

When the probed URL is a playlist or channel, a scrollable queue list appears between the metadata
card and the button row. The single-video layout is unchanged.

### Window states

| State | Shown |
|---|---|
| Empty | URL field only; window collapses to its minimum height |
| Probing | URL field + skeleton metadata card with a spinner |
| Ready | Metadata card, format menu, Options disclosure, Download button |
| Downloading | Determinate progress bar with speed and ETA; Download button becomes Cancel |
| Processing | Indeterminate bar labeled with the active stage (Merging / Removing sponsors / Extracting audio) |
| Done | Green check, "Reveal in Finder" and "Play" buttons; auto-returns to Empty after 8 s |
| Error | One-sentence message, "Details" disclosure with raw stderr, "Copy" button |

### Settings window

Persistent, applied to every download: download folder (default `~/Downloads`), SponsorBlock
categories, codec preference on/off, concurrent fragments (default 4), default audio format,
subtitle languages, cookie browser, and a "Check for yt-dlp updates" row showing the current
version.

### macOS integration

- On `windowDidBecomeKey`, if the clipboard holds an http(s) URL that differs from the field's
  current contents, prefill the field and begin probing. Never overwrite text the user typed.
- Dropping a link onto the dock icon or the window fills the field.
- `UNUserNotificationCenter` notification on completion with "Reveal in Finder" and "Play" actions.
- Dock icon shows aggregate download progress via `NSApp.dockTile`.

## Architecture

One target, no external dependencies. Everything that makes a decision is a pure function;
the process-spawning layer is deliberately trivial.

| Type | Responsibility | Depends on |
|---|---|---|
| `DownloadOptions` | Value type holding every drawer toggle plus the persisted settings that affect argv | — |
| `ArgumentBuilder` | `argv(url:options:) -> [String]` | `DownloadOptions` |
| `FormatCatalog` | `options(from: [RawFormat]) -> [FormatChoice]` — collapses yt-dlp's format list to the handful of heights actually available | — |
| `ProgressParser` | `parse(_ line: String) -> ProgressEvent?` | — |
| `MediaInfo` | Decoded `--dump-json` payload: title, uploader, duration, thumbnail URL, formats, chapters, playlist entries | — |
| `MediaProbe` | Runs the probe, decodes `MediaInfo` | `ProcessRunner` |
| `ProcessRunner` | Protocol: `run(_ argv: [String]) -> AsyncStream<Line>`. `SystemProcessRunner` is the only production conformance | Foundation |
| `DownloadQueue` | `@Observable`; owns jobs, serializes them, publishes progress and terminal state | `ProcessRunner`, `ProgressParser` |
| `ErrorMapper` | `message(forStderr:) -> String` | — |
| `BinaryManager` | First-run copy of yt-dlp to Application Support, update checks, resolves bundled ffmpeg path | Foundation |
| `AppSettings` | `@AppStorage`-backed persisted settings; holds the download folder as a bookmark | — |

`ArgumentBuilder`, `FormatCatalog`, `ProgressParser`, and `ErrorMapper` have no dependencies and no
side effects. They carry the test suite.

## Data flow

```
URL appears (paste / clipboard / drag)
      │  debounce 400 ms
      ▼
MediaProbe ── -J ──► MediaInfo ──► metadata card + FormatCatalog → format menu
      │                            (playlist? → queue list appears)
      ▼  Download pressed
ArgumentBuilder.argv ──► ProcessRunner ──► stdout lines ──► ProgressParser
                                                                 │
                                            progress bar ◄───────┘
                                                                 ▼
                                     exit 0 → notification + Reveal in Finder
                                     exit ≠ 0 → ErrorMapper → error state
```

## Binary management

On first launch, `BinaryManager` copies `Contents/Resources/yt-dlp` to
`~/Library/Application Support/YTDLP/bin/yt-dlp` and marks it executable. All invocations use that
copy, because `yt-dlp -U` rewrites its own binary and doing so inside the app bundle would
invalidate the code signature.

ffmpeg stays in the bundle at `Contents/Resources/ffmpeg` and is passed with `--ffmpeg-location`;
it never self-updates.

On launch (at most once per 24 h) the app runs `yt-dlp --update-to stable` in the background and
surfaces the result only if it fails. If the Application Support copy is missing or fails
`--version`, it is re-seeded from the bundle.

## Argument construction

`ArgumentBuilder` is the single place argv is assembled. No other type may build yt-dlp arguments.

**Always applied:**

```
--newline
--progress-template  dl:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s
--ffmpeg-location    <bundle>/Contents/Resources/ffmpeg
--paths              <download folder>
-o                   %(title)s.%(ext)s
-N                   <concurrency>
-R infinite --fragment-retries infinite
--embed-metadata
--embed-chapters
```

**Video mode** (the default):

```
-f  bv*[height<=N]+ba/b[height<=N]        (N from the format menu; omitted for "Best")
-S  vcodec:h264,acodec:aac                 (when codec preference is on)
--merge-output-format mp4
```

Height is used rather than the probed format id, because format ids can change between the probe
and the download.

**Audio only:**

```
-f ba/b -x --audio-format <m4a|mp3|opus> --audio-quality 0 --embed-thumbnail
```

**SponsorBlock** (when categories are configured): `--sponsorblock-remove <categories>`

**Clip:** `--download-sections *HH:MM:SS-HH:MM:SS --force-keyframes-at-cuts`

**Subtitles:** `--write-subs --write-auto-subs --sub-langs <langs> --embed-subs --convert-subs srt`

**Playlist:** `--yes-playlist --download-archive <app support>/archive.txt`, and the base `-o`
template is *replaced* by `%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s` so that
exactly one `-o` is ever emitted. Single video: `--no-playlist`.

**Cookies:** `--cookies-from-browser <browser>`

### Option conflicts

These are resolved in `ArgumentBuilder` and reflected in the UI, not left to yt-dlp:

| Conflict | Resolution |
|---|---|
| Clip range + SponsorBlock | Clip wins; SponsorBlock arguments are omitted and the drawer shows "Sponsor removal is off while clipping." Cutting twice produces unreliable output. |
| Audio only + subtitles | The subtitles checkbox is disabled; audio containers cannot embed subtitles. |
| Audio only + format menu | The format menu is disabled and shows "Audio". |
| Playlist + clip range | The clip fields are disabled; a time range is meaningless across many videos. |

## Error handling

`ErrorMapper` reduces stderr to one sentence, with raw output behind a "Details" disclosure:

| stderr contains | Message |
|---|---|
| `Sign in to confirm your age`, `members-only`, `Private video` | "This video needs a login — try turning on Use Safari cookies." |
| `Video unavailable`, `has been removed` | "This video isn't available." |
| `Unsupported URL` | "yt-dlp doesn't recognise this site." |
| `ffmpeg not found` | "The bundled ffmpeg is missing — reinstall the app." |
| anything else | The first non-empty stderr line, verbatim |

Transient network failures are yt-dlp's own concern via `-R infinite`; the UI shows "Retrying…"
when a retry line appears and does not treat it as an error.

Cancelling a download sends `SIGINT` (not `SIGKILL`) so yt-dlp cleans up its `.part` files, then
waits up to 3 s before escalating.

## Testing

No test spawns a process. `ProcessRunner` is faked throughout.

- **`ArgumentBuilder`** — the bulk of the suite. One test per option, plus explicit tests for each
  row of the conflict table above, asserting the exact argv array.
- **`ProgressParser`** — parametrised over real captured output lines, including the malformed and
  partial lines that appear when yt-dlp switches stages mid-line.
- **`FormatCatalog`** — against a checked-in `--dump-json` fixture, asserting that a video offering
  144p–2160p collapses to the expected menu and that audio-only sources produce no video choices.
- **`MediaInfo` decoding** — against the same fixture plus a playlist fixture.
- **`ErrorMapper`** — one test per table row, plus the fallthrough case.

## Out of scope

In-app video player, download scheduling, a browser extension, iCloud sync, format conversion
beyond what yt-dlp performs, Mac App Store distribution, and a menu bar item.

## Repository

`~/Developer/YTDLP`, a fresh git repository. The existing AppleScript applet at
`/Users/oleheinrichs/Applications/yt-dlp` is left untouched until the new app works.
