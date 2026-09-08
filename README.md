# YTDLP

A small macOS app that wraps [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) in a native SwiftUI
interface. Paste a URL, see what it is, pick a quality, download it.

It replaces the usual routine of switching to Terminal and remembering flags. Playlists become a
queue you can watch and cancel per-item; progress shows on the Dock icon; a notification and a
"Reveal in Finder" button land when a download finishes.

## Requirements

- **macOS 15 or later** (the deployment target is 15.0)
- **Xcode 16 or later** — the code is Swift 6 with strict concurrency enabled
- **`yt-dlp` and `ffmpeg`**, installed via Homebrew:

```bash
brew install yt-dlp ffmpeg
```

- **`deno` (optional)** — only needed for sites whose extractor runs JavaScript, which in practice
  means YouTube. Without it those specific downloads degrade; the rest of the app is unaffected.

```bash
brew install deno
```

The app looks for all three at the standard Homebrew locations (`/opt/homebrew/bin` on Apple
Silicon, `/usr/local/bin` on Intel) and tells you what's missing in Settings. It does **not** bundle
them — Homebrew's `yt-dlp` is a launcher script whose shebang points into a versioned Cellar
directory, and `ffmpeg` links a pile of dylibs from that same directory, so neither survives being
copied elsewhere. Updates come from `brew upgrade`, not from inside the app.

## Building

There is no notarized release to download. Gatekeeper blocks unsigned, unsandboxed apps from other
people's machines, and this one is deliberately unsandboxed — the App Sandbox cannot read browser
cookie stores, which would break `--cookies-from-browser`. So you build it yourself:

```bash
git clone https://github.com/O5ka01/YTDLP.git
cd YTDLP
open YTDLP.xcodeproj
```

In Xcode, select the **YTDLP** scheme and press **⌘R**.

The project uses automatic signing with no team baked in, so the first build will ask you to pick
one. A free personal Apple ID team is enough — go to the **YTDLP** target → **Signing & Capabilities**
and choose your team from the dropdown. You may also want to change the bundle identifier
(`com.oleheinrichs.YTDLP`) to something of your own.

## Running the tests

The pure logic — argument construction, progress parsing, error mapping, format collapsing, JSON
decoding — lives in a separate `YTDLPCore` package with no UI dependencies, so it tests from the
command line without Xcode:

```bash
cd YTDLPCore
swift test
```

## What it does

- **Paste, drop, or copy a URL.** The app probes it with `yt-dlp -J` and shows the thumbnail,
  title, channel and duration. A URL already on the clipboard when you switch to the app fills the
  field automatically, and you can drag a link onto the Dock icon.
- **Pick a quality** from a short menu collapsed out of yt-dlp's long format list, labelled with
  resolution and file size.
- **Per-download options** in a collapsible drawer: audio only (with a format and codec choice),
  subtitles, a start/end clip range, and using cookies from your browser for logged-in content.
- **Playlists and channels** appear as a queue. Downloads run one at a time; each row can be
  cancelled on its own.
- **Settings** for the download folder, default audio format, subtitle languages, which browser to
  take cookies from, SponsorBlock categories, Apple-friendly codecs, and fragment concurrency.

## Layout

| Path | What's in it |
|---|---|
| `YTDLP/` | The SwiftUI app — views, `AppSettings`, `DownloadQueue`, and the services that talk to the child processes |
| `YTDLPCore/` | Dependency-free logic package plus its tests |
| `docs/` | The original design spec, the implementation plan, and `KNOWN-ISSUES.md` |
| `tools/` | A Swift script that renders the app icon |

## Known issues

This was built for one person's Mac, and a handful of rough edges were triaged as
"ship as-is" rather than fixed. They're written down honestly — behaviour quirks, deliberate
divergences from the design spec, and code that could be tidier — in
[`docs/KNOWN-ISSUES.md`](docs/KNOWN-ISSUES.md). Worth a read before you file a bug.

## Licence

MIT. See [LICENSE](LICENSE).
