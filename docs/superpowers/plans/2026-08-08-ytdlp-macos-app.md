# yt-dlp macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A minimal SwiftUI macOS app that drives `yt-dlp`, replacing an AppleScript applet that opens Terminal.

**Architecture:** Two units. `YTDLPCore` is a local Swift package holding every decision the app makes as a pure function — argument building, progress parsing, format selection, error mapping — tested with `swift test` in about a second. `YTDLP` is the Xcode app target: SwiftUI views plus the thin process-spawning and file-system layer. The app depends on the package; the package knows nothing about the app.

**Tech Stack:** Swift 6.3, SwiftUI, swift-testing (`import Testing`), no third-party dependencies.

## Global Constraints

- **Deployment target:** macOS 15.0. **Swift language version:** 6.0.
- **Bundle identifier:** `com.oleheinrichs.YTDLP`.
- **No third-party dependencies.** Not in `Package.swift`, not in the Xcode project.
- **App Sandbox is OFF** (`YTDLP.entitlements` sets `com.apple.security.app-sandbox` to `false`). `--cookies-from-browser` cannot read browser cookie stores under the sandbox. Do not enable it.
- **Signing is ad-hoc** (`Sign to Run Locally`). No Apple Developer account. Xcode automatically disables hardened runtime for ad-hoc builds; this is expected and not an error.
- **Everything in `YTDLPCore` must be `Sendable` and free of side effects.** No `Foundation.Process`, no file I/O, no `UserDefaults` in the package. If a type needs any of those, it belongs in the app target.
- **Only `ArgumentBuilder` may construct yt-dlp arguments.** No other type builds argv, anywhere.
- **Verbatim progress template** (used in code and in tests):
  `dl:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s`
- **Spec:** `docs/superpowers/specs/2026-08-08-ytdlp-macos-app-design.md`. Read it before Task 1.

## File Structure

```
~/Developer/YTDLP/
├── YTDLP.xcodeproj/project.pbxproj      Hand-written; synchronized folder group
├── YTDLP/                               App target. Xcode picks up new files automatically
│   ├── YTDLPApp.swift                   @main, Window scene, Settings scene
│   ├── YTDLP.entitlements               Sandbox off
│   ├── Assets.xcassets/                 AppIcon
│   ├── Model/
│   │   ├── AppSettings.swift            @AppStorage-backed persisted settings
│   │   └── DownloadQueue.swift          @Observable; owns jobs, serializes them
│   ├── Services/
│   │   ├── SystemProcessRunner.swift    The only ProcessRunner conformance
│   │   ├── BinaryManager.swift          Seeds/updates yt-dlp in Application Support
│   │   ├── MediaProbe.swift             Runs -J, decodes MediaInfo
│   │   └── Notifier.swift               UserNotifications + Reveal in Finder
│   └── Views/
│       ├── ContentView.swift            URL field, state machine, button row
│       ├── MetadataCard.swift           Thumbnail, title, uploader, duration
│       ├── OptionsDrawer.swift          Per-download toggles
│       ├── QueueList.swift              Playlist entries
│       └── SettingsView.swift           Persistent preferences
└── YTDLPCore/                           Local Swift package. Pure logic only
    ├── Package.swift
    ├── Sources/YTDLPCore/
    │   ├── DownloadOptions.swift        Value types describing a download
    │   ├── OptionResolver.swift         Applies the conflict rules, emits notices
    │   ├── ArgumentBuilder.swift        options -> [String] argv
    │   ├── MediaInfo.swift              Decodable model of `yt-dlp -J` output
    │   ├── FormatCatalog.swift          RawFormat[] -> FormatChoice[]
    │   ├── ProgressParser.swift         One stdout line -> ProgressEvent
    │   ├── ErrorMapper.swift            stderr -> one friendly sentence
    │   └── ProcessRunner.swift          Protocol + ProcessEvent
    └── Tests/YTDLPCoreTests/
        ├── ArgumentBuilderTests.swift
        ├── OptionResolverTests.swift
        ├── MediaInfoTests.swift
        ├── FormatCatalogTests.swift
        ├── ProgressParserTests.swift
        ├── ErrorMapperTests.swift
        └── Fixtures/
            ├── single-video.json
            └── playlist.json
```

Tasks 1–9 build `YTDLPCore` and are pure TDD. Tasks 10–17 build the app target and are verified by building and running. Run `swift test` from `YTDLPCore/` after every core change; run `xcodebuild` after every app change.

---

### Task 1: Project skeleton that builds and launches

**Files:**
- Create: `YTDLP.xcodeproj/project.pbxproj`
- Create: `YTDLP/YTDLPApp.swift`, `YTDLP/ContentView.swift`, `YTDLP/YTDLP.entitlements`
- Create: `YTDLP/Assets.xcassets/Contents.json`, `YTDLP/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `YTDLPCore/Package.swift`, `YTDLPCore/Sources/YTDLPCore/ProcessRunner.swift`
- Create: `YTDLPCore/Tests/YTDLPCoreTests/ProcessRunnerTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable `YTDLP` scheme; `YTDLPCore.ProcessEvent`; the `ProcessRunner` protocol every later service is written against.

> **Note on the project file:** this exact `project.pbxproj` has been verified to build with Xcode 26.6. It uses a `PBXFileSystemSynchronizedRootGroup`, which means the `YTDLP/` folder is synchronized — new `.swift` files added anywhere under it are compiled automatically and **must not** be registered in the project file. Never hand-edit `project.pbxproj` after this task.

- [ ] **Step 1: Create the directory layout**

```bash
cd ~/Developer/YTDLP
mkdir -p YTDLP.xcodeproj YTDLP/Model YTDLP/Services YTDLP/Views \
         YTDLP/Assets.xcassets/AppIcon.appiconset \
         YTDLPCore/Sources/YTDLPCore YTDLPCore/Tests/YTDLPCoreTests/Fixtures
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.DS_Store
DerivedData/
DD/
.build/
*.xcuserstate
xcuserdata/
YTDLP/Resources/yt-dlp
YTDLP/Resources/ffmpeg
```

- [ ] **Step 3: Write `YTDLP.xcodeproj/project.pbxproj`**

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		AA0000000000000000000010 /* YTDLPCore in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000011 /* YTDLPCore */; };
/* End PBXBuildFile section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		AA0000000000000000000001 /* YTDLP */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = YTDLP;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		AA0000000000000000000002 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000010 /* YTDLPCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		AA0000000000000000000003 = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000001 /* YTDLP */,
				AA0000000000000000000004 /* Products */,
			);
			sourceTree = "<group>";
		};
		AA0000000000000000000004 /* Products */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000005 /* YTDLP.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AA0000000000000000000006 /* YTDLP */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000007 /* Build configuration list for PBXNativeTarget "YTDLP" */;
			buildPhases = (
				AA0000000000000000000008 /* Sources */,
				AA0000000000000000000002 /* Frameworks */,
				AA0000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000001 /* YTDLP */,
			);
			name = YTDLP;
			packageProductDependencies = (
				AA0000000000000000000011 /* YTDLPCore */,
			);
			productName = YTDLP;
			productReference = AA0000000000000000000005 /* YTDLP.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AA000000000000000000000A /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2660;
				LastUpgradeCheck = 2660;
				TargetAttributes = {
					AA0000000000000000000006 = {
						CreatedOnToolsVersion = 26.6;
					};
				};
			};
			buildConfigurationList = AA000000000000000000000B /* Build configuration list for PBXProject "YTDLP" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = AA0000000000000000000003;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			packageReferences = (
				AA0000000000000000000012 /* XCLocalSwiftPackageReference "YTDLPCore" */,
			);
			productRefGroup = AA0000000000000000000004 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				AA0000000000000000000006 /* YTDLP */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		AA0000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		AA0000000000000000000008 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXFileReference section */
		AA0000000000000000000005 /* YTDLP.app */ = {
			isa = PBXFileReference;
			explicitFileType = wrapper.application;
			includeInIndex = 0;
			path = YTDLP.app;
			sourceTree = BUILT_PRODUCTS_DIR;
		};
/* End PBXFileReference section */

/* Begin XCBuildConfiguration section */
		AA000000000000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_OBJC_WEAK = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		AA000000000000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_OBJC_WEAK = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 6.0;
			};
			name = Release;
		};
		AA000000000000000000000E /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = YTDLP/YTDLP.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.oleheinrichs.YTDLP;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
			};
			name = Debug;
		};
		AA000000000000000000000F /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = YTDLP/YTDLP.entitlements;
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities";
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.oleheinrichs.YTDLP;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		AA000000000000000000000B /* Build configuration list for PBXProject "YTDLP" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA000000000000000000000C /* Debug */,
				AA000000000000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000007 /* Build configuration list for PBXNativeTarget "YTDLP" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA000000000000000000000E /* Debug */,
				AA000000000000000000000F /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		AA0000000000000000000012 /* XCLocalSwiftPackageReference "YTDLPCore" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = YTDLPCore;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		AA0000000000000000000011 /* YTDLPCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = YTDLPCore;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = AA000000000000000000000A /* Project object */;
}
```

- [ ] **Step 4: Write the package manifest `YTDLPCore/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTDLPCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "YTDLPCore", targets: ["YTDLPCore"])],
    targets: [
        .target(name: "YTDLPCore"),
        .testTarget(
            name: "YTDLPCoreTests",
            dependencies: ["YTDLPCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 5: Write the failing test `YTDLPCore/Tests/YTDLPCoreTests/ProcessRunnerTests.swift`**

```swift
import Testing
@testable import YTDLPCore

@Test func processEventsAreEquatable() {
    #expect(ProcessEvent.stdout("a") == ProcessEvent.stdout("a"))
    #expect(ProcessEvent.stdout("a") != ProcessEvent.stderr("a"))
    #expect(ProcessEvent.exit(code: 0) != ProcessEvent.exit(code: 1))
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: FAIL, `cannot find 'ProcessEvent' in scope`.

- [ ] **Step 7: Write `YTDLPCore/Sources/YTDLPCore/ProcessRunner.swift`**

```swift
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
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 1 test.

- [ ] **Step 9: Write the app entry point `YTDLP/YTDLPApp.swift`**

```swift
import SwiftUI

@main
struct YTDLPApp: App {
    var body: some Scene {
        Window("yt-dlp", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 10: Write a placeholder `YTDLP/ContentView.swift`**

```swift
import SwiftUI
import YTDLPCore

struct ContentView: View {
    var body: some View {
        Text("yt-dlp")
            .padding(40)
    }
}
```

- [ ] **Step 11: Write `YTDLP/YTDLP.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
</dict>
</plist>
```

- [ ] **Step 12: Write the asset catalog stubs**

`YTDLP/Assets.xcassets/Contents.json`:

```json
{"info":{"author":"xcode","version":1}}
```

`YTDLP/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{"images":[{"idiom":"mac","scale":"1x","size":"512x512"},{"idiom":"mac","scale":"2x","size":"512x512"}],"info":{"author":"xcode","version":1}}
```

- [ ] **Step 13: Build the app**

Run: `cd ~/Developer/YTDLP && xcodebuild -project YTDLP.xcodeproj -scheme YTDLP -configuration Debug -derivedDataPath ./DD build 2>&1 | grep -E "^\*\*|error:"`
Expected: `** BUILD SUCCEEDED **`. A `note: Disabling hardened runtime with ad-hoc codesigning.` line is expected and is not an error.

- [ ] **Step 14: Launch it once to confirm it runs**

Run: `open ~/Developer/YTDLP/DD/Build/Products/Debug/YTDLP.app`
Expected: a small window titled "yt-dlp" reading "yt-dlp". Quit it.

- [ ] **Step 15: Commit**

```bash
cd ~/Developer/YTDLP
git add -A
git commit -m "feat: project skeleton with local YTDLPCore package"
```

---

### Task 2: DownloadOptions value types

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/DownloadOptions.swift`
- Test: `YTDLPCore/Tests/YTDLPCoreTests/OptionResolverTests.swift` (created here, extended in Task 3)

**Interfaces:**
- Consumes: nothing.
- Produces: `MediaMode`, `AudioFormat`, `TimeRange`, `DownloadOptions`. Every later task refers to these exact names.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import YTDLPCore

@Test func timeRangeFormatsAsYtDlpSection() {
    let range = TimeRange(start: "00:01:30", end: "00:02:45")
    #expect(range.sectionArgument == "*00:01:30-00:02:45")
}

@Test func defaultOptionsAreVideoBestQuality() {
    let options = DownloadOptions.preview
    #expect(options.mode == .video(maxHeight: nil))
    #expect(options.clip == nil)
    #expect(options.subtitleLanguages == nil)
    #expect(options.cookieBrowser == nil)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter timeRangeFormats`
Expected: FAIL, `cannot find 'TimeRange' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum AudioFormat: String, Equatable, Sendable, CaseIterable {
    case m4a, mp3, opus
}

public enum MediaMode: Equatable, Sendable {
    /// `maxHeight == nil` means "Best available".
    case video(maxHeight: Int?)
    case audio(format: AudioFormat)
}

public struct TimeRange: Equatable, Sendable {
    public let start: String    // "HH:MM:SS"
    public let end: String      // "HH:MM:SS"

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    /// The value passed to `--download-sections`.
    public var sectionArgument: String { "*\(start)-\(end)" }
}

/// Everything that determines the argv for one download.
///
/// Fields above the divider come from the Options drawer and reset after each
/// download; fields below come from Settings and persist.
public struct DownloadOptions: Equatable, Sendable {
    public var mode: MediaMode
    public var isPlaylist: Bool
    public var clip: TimeRange?
    /// `nil` means subtitles are off.
    public var subtitleLanguages: [String]?
    /// `nil` means cookies are off. Otherwise a yt-dlp browser name, e.g. "safari".
    public var cookieBrowser: String?

    public var sponsorBlockCategories: [String]
    public var preferAppleCodecs: Bool
    public var concurrentFragments: Int
    public var downloadFolder: String
    public var ffmpegPath: String
    public var archivePath: String

    public init(
        mode: MediaMode = .video(maxHeight: nil),
        isPlaylist: Bool = false,
        clip: TimeRange? = nil,
        subtitleLanguages: [String]? = nil,
        cookieBrowser: String? = nil,
        sponsorBlockCategories: [String] = [],
        preferAppleCodecs: Bool = true,
        concurrentFragments: Int = 4,
        downloadFolder: String,
        ffmpegPath: String,
        archivePath: String
    ) {
        self.mode = mode
        self.isPlaylist = isPlaylist
        self.clip = clip
        self.subtitleLanguages = subtitleLanguages
        self.cookieBrowser = cookieBrowser
        self.sponsorBlockCategories = sponsorBlockCategories
        self.preferAppleCodecs = preferAppleCodecs
        self.concurrentFragments = concurrentFragments
        self.downloadFolder = downloadFolder
        self.ffmpegPath = ffmpegPath
        self.archivePath = archivePath
    }

    /// Fixed values used by tests and SwiftUI previews so assertions stay readable.
    public static let preview = DownloadOptions(
        downloadFolder: "/Users/me/Downloads",
        ffmpegPath: "/App/ffmpeg",
        archivePath: "/App/archive.txt"
    )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: DownloadOptions value types"
```

---

### Task 3: OptionResolver and the conflict rules

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/OptionResolver.swift`
- Modify: `YTDLPCore/Tests/YTDLPCoreTests/OptionResolverTests.swift`

**Interfaces:**
- Consumes: `DownloadOptions`, `MediaMode`, `TimeRange` (Task 2).
- Produces: `OptionNotice` enum, `ResolvedOptions` struct, `OptionResolver.resolve(_:) -> ResolvedOptions`. Task 4's `ArgumentBuilder.argv` takes `ResolvedOptions`, never raw `DownloadOptions`. Task 14's drawer reads `notices` to grey out controls.

This is where the spec's conflict table lives. Resolving conflicts here — rather than letting yt-dlp fail — is the whole point: the UI and the argv can never disagree, because both read the same resolved value.

- [ ] **Step 1: Write the failing tests (append to `OptionResolverTests.swift`)**

```swift
@Test func clipDisablesSponsorBlock() {
    var raw = DownloadOptions.preview
    raw.sponsorBlockCategories = ["sponsor", "intro"]
    raw.clip = TimeRange(start: "00:01:00", end: "00:02:00")

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.sponsorBlockCategories.isEmpty)
    #expect(resolved.options.clip == raw.clip)
    #expect(resolved.notices == [.sponsorBlockDisabledByClip])
}

@Test func audioModeDisablesSubtitles() {
    var raw = DownloadOptions.preview
    raw.mode = .audio(format: .m4a)
    raw.subtitleLanguages = ["en"]

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.subtitleLanguages == nil)
    #expect(resolved.notices == [.subtitlesUnavailableInAudioMode])
}

@Test func playlistDisablesClip() {
    var raw = DownloadOptions.preview
    raw.isPlaylist = true
    raw.clip = TimeRange(start: "00:01:00", end: "00:02:00")

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.clip == nil)
    #expect(resolved.notices == [.clipUnavailableForPlaylist])
}

@Test func playlistDroppingClipLeavesSponsorBlockOn() {
    var raw = DownloadOptions.preview
    raw.isPlaylist = true
    raw.clip = TimeRange(start: "00:01:00", end: "00:02:00")
    raw.sponsorBlockCategories = ["sponsor"]

    let resolved = OptionResolver.resolve(raw)

    #expect(resolved.options.sponsorBlockCategories == ["sponsor"])
    #expect(resolved.notices == [.clipUnavailableForPlaylist])
}

@Test func cleanOptionsProduceNoNotices() {
    #expect(OptionResolver.resolve(.preview).notices.isEmpty)
}
```

The fourth test is the important one: the playlist rule must run *before* the clip rule, or a playlist would silently lose SponsorBlock because of a clip that was itself discarded.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter OptionResolver`
Expected: FAIL, `cannot find 'OptionResolver' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// A control the resolver switched off, and why. Surfaced in the Options drawer.
public enum OptionNotice: String, Equatable, Sendable, CaseIterable {
    case sponsorBlockDisabledByClip
    case subtitlesUnavailableInAudioMode
    case clipUnavailableForPlaylist

    public var message: String {
        switch self {
        case .sponsorBlockDisabledByClip:
            "Sponsor removal is off while clipping."
        case .subtitlesUnavailableInAudioMode:
            "Audio files can't carry subtitles."
        case .clipUnavailableForPlaylist:
            "A time range doesn't apply to a playlist."
        }
    }
}

public struct ResolvedOptions: Equatable, Sendable {
    public let options: DownloadOptions
    public let notices: [OptionNotice]
}

/// Applies the option conflict rules from the design spec.
///
/// Order matters: the playlist rule drops the clip first, so that a playlist
/// does not lose SponsorBlock to a clip that was itself discarded.
public enum OptionResolver {
    public static func resolve(_ raw: DownloadOptions) -> ResolvedOptions {
        var options = raw
        var notices: [OptionNotice] = []

        if options.isPlaylist, options.clip != nil {
            options.clip = nil
            notices.append(.clipUnavailableForPlaylist)
        }

        if options.clip != nil, !options.sponsorBlockCategories.isEmpty {
            options.sponsorBlockCategories = []
            notices.append(.sponsorBlockDisabledByClip)
        }

        if case .audio = options.mode, options.subtitleLanguages != nil {
            options.subtitleLanguages = nil
            notices.append(.subtitlesUnavailableInAudioMode)
        }

        return ResolvedOptions(options: options, notices: notices)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: OptionResolver applies option conflict rules"
```

---

### Task 4: ArgumentBuilder — base arguments and media mode

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/ArgumentBuilder.swift`
- Test: `YTDLPCore/Tests/YTDLPCoreTests/ArgumentBuilderTests.swift`

**Interfaces:**
- Consumes: `ResolvedOptions` (Task 3).
- Produces: `ArgumentBuilder.argv(url:options:) -> [String]` and `ArgumentBuilder.progressTemplate`. Task 12's `DownloadQueue` and Task 13's `MediaProbe` both call this and nothing else.

Tests assert on `contains` of a contiguous slice rather than whole-array equality, so that adding an unrelated flag later doesn't break every test. A helper makes that readable.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import YTDLPCore

/// True if `argv` contains `slice` as a contiguous run.
private func contains(_ argv: [String], _ slice: [String]) -> Bool {
    guard !slice.isEmpty, argv.count >= slice.count else { return false }
    return (0...(argv.count - slice.count)).contains { start in
        Array(argv[start..<(start + slice.count)]) == slice
    }
}

private func argv(_ transform: (inout DownloadOptions) -> Void = { _ in }) -> [String] {
    var raw = DownloadOptions.preview
    transform(&raw)
    return ArgumentBuilder.argv(url: "URL", options: OptionResolver.resolve(raw))
}

@Test func alwaysAppliedArgumentsArePresent() {
    let result = argv()
    #expect(result.contains("--newline"))
    #expect(contains(result, ["--progress-template", ArgumentBuilder.progressTemplate]))
    #expect(contains(result, ["--ffmpeg-location", "/App/ffmpeg"]))
    #expect(contains(result, ["--paths", "/Users/me/Downloads"]))
    #expect(contains(result, ["-N", "4"]))
    #expect(result.contains("--embed-metadata"))
    #expect(result.contains("--embed-chapters"))
    #expect(result.last == "URL")
}

@Test func urlIsLastSoItIsNeverParsedAsAFlagValue() {
    #expect(argv { $0.cookieBrowser = "safari" }.last == "URL")
}

@Test func bestVideoUsesNoHeightCap() {
    let result = argv { $0.mode = .video(maxHeight: nil) }
    #expect(contains(result, ["-f", "bv*+ba/b"]))
    #expect(contains(result, ["--merge-output-format", "mp4"]))
}

@Test func cappedVideoFiltersOnHeight() {
    let result = argv { $0.mode = .video(maxHeight: 1080) }
    #expect(contains(result, ["-f", "bv*[height<=1080]+ba/b[height<=1080]"]))
}

@Test func appleCodecPreferenceAddsSortOrder() {
    #expect(contains(argv { $0.preferAppleCodecs = true }, ["-S", "vcodec:h264,acodec:aac"]))
    #expect(!argv { $0.preferAppleCodecs = false }.contains("-S"))
}

@Test func audioModeExtractsAndEmbedsThumbnail() {
    let result = argv { $0.mode = .audio(format: .m4a) }
    #expect(contains(result, ["-f", "ba/b"]))
    #expect(result.contains("-x"))
    #expect(contains(result, ["--audio-format", "m4a"]))
    #expect(contains(result, ["--audio-quality", "0"]))
    #expect(result.contains("--embed-thumbnail"))
    #expect(!result.contains("--merge-output-format"))
    #expect(!result.contains("-S"))
}

@Test func singleVideoOptsOutOfPlaylists() {
    #expect(argv().contains("--no-playlist"))
}
```

Note the third assertion in `audioModeExtractsAndEmbedsThumbnail`: `-S` is a video sort order and must not appear in audio mode even when `preferAppleCodecs` is on.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter ArgumentBuilder`
Expected: FAIL, `cannot find 'ArgumentBuilder' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Builds the yt-dlp command line. The only place in the codebase that does so.
public enum ArgumentBuilder {
    /// Kept verbatim in the spec; `ProgressParser` parses exactly this shape.
    public static let progressTemplate =
        "dl:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"

    public static func argv(url: String, options resolved: ResolvedOptions) -> [String] {
        let options = resolved.options
        var argv: [String] = [
            "--newline",
            "--progress-template", progressTemplate,
            "--ffmpeg-location", options.ffmpegPath,
            "--paths", options.downloadFolder,
            "-N", String(options.concurrentFragments),
            "-R", "infinite",
            "--fragment-retries", "infinite",
            "--embed-metadata",
            "--embed-chapters",
        ]

        argv += outputArguments(options)
        argv += modeArguments(options)
        argv += featureArguments(options)
        argv.append(url)
        return argv
    }

    private static func outputArguments(_ options: DownloadOptions) -> [String] {
        if options.isPlaylist {
            return [
                "--yes-playlist",
                "--download-archive", options.archivePath,
                "-o", "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s",
            ]
        }
        return ["--no-playlist", "-o", "%(title)s.%(ext)s"]
    }

    private static func modeArguments(_ options: DownloadOptions) -> [String] {
        switch options.mode {
        case .video(let maxHeight):
            let selector = maxHeight.map { "bv*[height<=\($0)]+ba/b[height<=\($0)]" } ?? "bv*+ba/b"
            var argv = ["-f", selector, "--merge-output-format", "mp4"]
            if options.preferAppleCodecs {
                argv += ["-S", "vcodec:h264,acodec:aac"]
            }
            return argv

        case .audio(let format):
            return [
                "-f", "ba/b",
                "-x",
                "--audio-format", format.rawValue,
                "--audio-quality", "0",
                "--embed-thumbnail",
            ]
        }
    }

    private static func featureArguments(_ options: DownloadOptions) -> [String] {
        var argv: [String] = []

        if !options.sponsorBlockCategories.isEmpty {
            argv += ["--sponsorblock-remove", options.sponsorBlockCategories.joined(separator: ",")]
        }
        if let clip = options.clip {
            argv += ["--download-sections", clip.sectionArgument, "--force-keyframes-at-cuts"]
        }
        if let languages = options.subtitleLanguages, !languages.isEmpty {
            argv += [
                "--write-subs",
                "--write-auto-subs",
                "--sub-langs", languages.joined(separator: ","),
                "--embed-subs",
                "--convert-subs", "srt",
            ]
        }
        if let browser = options.cookieBrowser {
            argv += ["--cookies-from-browser", browser]
        }
        return argv
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ArgumentBuilder base and media-mode arguments"
```

---

### Task 5: ArgumentBuilder — feature flags and conflict integration

**Files:**
- Modify: `YTDLPCore/Tests/YTDLPCoreTests/ArgumentBuilderTests.swift`

**Interfaces:**
- Consumes: everything from Task 4. No new production code — `featureArguments` was written in Task 4; this task proves it and locks the conflict behaviour end to end.
- Produces: no new symbols.

The implementation already exists, so these tests should pass immediately. That is the point: they are regression locks on the spec's conflict table, written as a separate reviewable unit.

- [ ] **Step 1: Write the tests (append to `ArgumentBuilderTests.swift`)**

```swift
@Test func sponsorBlockJoinsCategoriesWithCommas() {
    let result = argv { $0.sponsorBlockCategories = ["sponsor", "selfpromo", "intro"] }
    #expect(contains(result, ["--sponsorblock-remove", "sponsor,selfpromo,intro"]))
}

@Test func noSponsorBlockArgumentWhenNoCategories() {
    #expect(!argv().contains("--sponsorblock-remove"))
}

@Test func clipAddsSectionAndKeyframeFlags() {
    let result = argv { $0.clip = TimeRange(start: "00:10:00", end: "00:15:00") }
    #expect(contains(result, ["--download-sections", "*00:10:00-00:15:00"]))
    #expect(result.contains("--force-keyframes-at-cuts"))
}

@Test func subtitlesJoinLanguagesAndConvertToSrt() {
    let result = argv { $0.subtitleLanguages = ["en", "de"] }
    #expect(result.contains("--write-subs"))
    #expect(result.contains("--write-auto-subs"))
    #expect(contains(result, ["--sub-langs", "en,de"]))
    #expect(result.contains("--embed-subs"))
    #expect(contains(result, ["--convert-subs", "srt"]))
}

@Test func emptySubtitleLanguageListEmitsNothing() {
    #expect(!argv { $0.subtitleLanguages = [] }.contains("--write-subs"))
}

@Test func cookiesNameTheBrowser() {
    #expect(contains(argv { $0.cookieBrowser = "safari" }, ["--cookies-from-browser", "safari"]))
}

@Test func playlistReplacesOutputTemplateAndAddsArchive() {
    let result = argv { $0.isPlaylist = true }
    #expect(result.contains("--yes-playlist"))
    #expect(!result.contains("--no-playlist"))
    #expect(contains(result, ["--download-archive", "/App/archive.txt"]))
    #expect(contains(result, ["-o", "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s"]))
    #expect(result.filter { $0 == "-o" }.count == 1)
}

@Test func clipWinsOverSponsorBlockInFinalArgv() {
    let result = argv {
        $0.sponsorBlockCategories = ["sponsor"]
        $0.clip = TimeRange(start: "00:01:00", end: "00:02:00")
    }
    #expect(!result.contains("--sponsorblock-remove"))
    #expect(result.contains("--download-sections"))
}

@Test func audioModeDropsSubtitlesInFinalArgv() {
    let result = argv {
        $0.mode = .audio(format: .mp3)
        $0.subtitleLanguages = ["en"]
    }
    #expect(!result.contains("--write-subs"))
    #expect(!result.contains("--embed-subs"))
}

@Test func playlistDropsClipInFinalArgv() {
    let result = argv {
        $0.isPlaylist = true
        $0.clip = TimeRange(start: "00:01:00", end: "00:02:00")
    }
    #expect(!result.contains("--download-sections"))
}
```

The `filter { $0 == "-o" }.count == 1` assertion is the guard against emitting two output templates for a playlist — the exact bug the spec calls out.

- [ ] **Step 2: Run the tests**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 25 tests. If any fail, fix `ArgumentBuilder`, not the test.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "test: lock ArgumentBuilder feature flags and conflict rules"
```

---

### Task 6: ProgressParser

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/ProgressParser.swift`
- Test: `YTDLPCore/Tests/YTDLPCoreTests/ProgressParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ProgressEvent`, `Stage`, `ProgressParser.parse(_:) -> ProgressEvent?`. Task 12's `DownloadQueue` feeds every stdout line through this.

Real yt-dlp output pads the percent field, so `dl: 42.5%|  1.23MiB/s|00:31` is typical. Percent and ETA read `Unknown` before the total size is known, and the parser must not crash or report 0% on those.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import YTDLPCore

@Test func parsesPaddedProgressLine() {
    let event = ProgressParser.parse("dl: 42.5%|  1.23MiB/s|00:31")
    #expect(event == .progress(percent: 42.5, speed: "1.23MiB/s", eta: "00:31"))
}

@Test func parsesHundredPercent() {
    #expect(ProgressParser.parse("dl:100.0%|  5.00MiB/s|00:00")
            == .progress(percent: 100, speed: "5.00MiB/s", eta: "00:00"))
}

@Test func unknownPercentIsIgnoredRatherThanReportedAsZero() {
    #expect(ProgressParser.parse("dl:Unknown|Unknown B/s|Unknown") == nil)
}

@Test func nonProgressLinesAreIgnored() {
    #expect(ProgressParser.parse("[youtube] Extracting URL: https://youtu.be/x") == nil)
    #expect(ProgressParser.parse("") == nil)
}

@Test func recognisesPostProcessingStages() {
    #expect(ProgressParser.parse(#"[Merger] Merging formats into "video.mp4""#) == .stage(.merging))
    #expect(ProgressParser.parse("[ModifyChapters] Removing chapters from video.mp4") == .stage(.removingSponsors))
    #expect(ProgressParser.parse("[ExtractAudio] Destination: audio.m4a") == .stage(.extractingAudio))
    #expect(ProgressParser.parse("[EmbedSubtitle] Embedding subtitles in video.mp4") == .stage(.embeddingSubtitles))
}

@Test func recognisesRetries() {
    #expect(ProgressParser.parse("[download] Got error: timed out. Retrying (1/10)...") == .retrying)
}

@Test func malformedProgressLineIsIgnoredNotCrashed() {
    #expect(ProgressParser.parse("dl:42.5%") == nil)
    #expect(ProgressParser.parse("dl:|||") == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter ProgressParser`
Expected: FAIL, `cannot find 'ProgressParser' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// A post-download step. These report no percentage, so the UI shows an
/// indeterminate bar rather than a fabricated one.
public enum Stage: Equatable, Sendable {
    case merging
    case removingSponsors
    case extractingAudio
    case embeddingSubtitles

    public var label: String {
        switch self {
        case .merging: "Merging…"
        case .removingSponsors: "Removing sponsors…"
        case .extractingAudio: "Extracting audio…"
        case .embeddingSubtitles: "Adding subtitles…"
        }
    }
}

public enum ProgressEvent: Equatable, Sendable {
    case progress(percent: Double, speed: String, eta: String)
    case stage(Stage)
    case retrying
}

/// Turns one line of yt-dlp stdout into an event, or `nil` if it carries nothing
/// the UI needs. Unparseable lines are always `nil` — never a crash, never 0%.
public enum ProgressParser {
    private static let stagePrefixes: [(String, Stage)] = [
        ("[Merger]", .merging),
        ("[ModifyChapters]", .removingSponsors),
        ("[SponsorBlock]", .removingSponsors),
        ("[ExtractAudio]", .extractingAudio),
        ("[EmbedSubtitle]", .embeddingSubtitles),
    ]

    public static func parse(_ line: String) -> ProgressEvent? {
        if line.hasPrefix("dl:") {
            return parseProgress(String(line.dropFirst(3)))
        }
        if line.contains("Retrying") {
            return .retrying
        }
        for (prefix, stage) in stagePrefixes where line.hasPrefix(prefix) {
            return .stage(stage)
        }
        return nil
    }

    private static func parseProgress(_ body: String) -> ProgressEvent? {
        let fields = body.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard fields.count == 3 else { return nil }

        let percentField = fields[0].hasSuffix("%") ? String(fields[0].dropLast()) : fields[0]
        guard let percent = Double(percentField) else { return nil }

        return .progress(percent: percent, speed: fields[1], eta: fields[2])
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 32 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ProgressParser for yt-dlp stdout"
```

---

### Task 7: ErrorMapper

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/ErrorMapper.swift`
- Test: `YTDLPCore/Tests/YTDLPCoreTests/ErrorMapperTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ErrorMapper.message(forStderr:) -> String`. Task 12 calls it on non-zero exit.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import YTDLPCore

@Test func ageRestrictionSuggestsCookies() {
    let stderr = "ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate for some users."
    #expect(ErrorMapper.message(forStderr: stderr)
            == "This video needs a login — try turning on Use Safari cookies.")
}

@Test func membersOnlyAndPrivateAlsoSuggestCookies() {
    #expect(ErrorMapper.message(forStderr: "ERROR: Join this channel to get access to members-only content")
            == "This video needs a login — try turning on Use Safari cookies.")
    #expect(ErrorMapper.message(forStderr: "ERROR: [youtube] abc: Private video. Sign in if you've been granted access")
            == "This video needs a login — try turning on Use Safari cookies.")
}

@Test func unavailableVideoIsReportedPlainly() {
    #expect(ErrorMapper.message(forStderr: "ERROR: [youtube] abc: Video unavailable")
            == "This video isn't available.")
    #expect(ErrorMapper.message(forStderr: "ERROR: This video has been removed by the uploader")
            == "This video isn't available.")
}

@Test func unsupportedSiteIsNamed() {
    #expect(ErrorMapper.message(forStderr: "ERROR: Unsupported URL: https://example.com/x")
            == "yt-dlp doesn't recognise this site.")
}

@Test func missingFfmpegPointsAtTheBundle() {
    #expect(ErrorMapper.message(forStderr: "ERROR: ffmpeg not found. Please install")
            == "The bundled ffmpeg is missing — reinstall the app.")
}

@Test func unrecognisedErrorFallsBackToFirstNonEmptyLine() {
    let stderr = "\n\nWARNING: something\nERROR: some brand new failure mode\n"
    #expect(ErrorMapper.message(forStderr: stderr) == "WARNING: something")
}

@Test func emptyStderrStillProducesAMessage() {
    #expect(ErrorMapper.message(forStderr: "   \n\n") == "The download failed for an unknown reason.")
}

@Test func matchingIsCaseInsensitive() {
    #expect(ErrorMapper.message(forStderr: "error: VIDEO UNAVAILABLE") == "This video isn't available.")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter ErrorMapper`
Expected: FAIL, `cannot find 'ErrorMapper' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 40 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ErrorMapper translates yt-dlp stderr"
```

---

### Task 8: MediaInfo decoding

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/MediaInfo.swift`
- Create: `YTDLPCore/Tests/YTDLPCoreTests/Fixtures/single-video.json`
- Create: `YTDLPCore/Tests/YTDLPCoreTests/Fixtures/playlist.json`
- Test: `YTDLPCore/Tests/YTDLPCoreTests/MediaInfoTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `RawFormat`, `PlaylistEntry`, `MediaInfo`, `MediaInfo.decode(from: Data) throws -> MediaInfo`. Task 13's `MediaProbe` calls `decode`; Task 9's `FormatCatalog` consumes `[RawFormat]`.

The fixtures below are trimmed real `yt-dlp -J` output — enough fields to exercise decoding without carrying a 400 KB file in the repo.

- [ ] **Step 1: Write `Fixtures/single-video.json`**

```json
{
  "id": "dQw4w9WgXcQ",
  "_type": "video",
  "title": "Never Gonna Give You Up",
  "uploader": "Rick Astley",
  "duration": 213,
  "thumbnail": "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
  "formats": [
    {"format_id": "139", "ext": "m4a", "vcodec": "none", "acodec": "mp4a.40.5", "filesize": 1258291},
    {"format_id": "160", "ext": "mp4", "height": 144, "vcodec": "avc1.4d400c", "acodec": "none", "filesize": 1887436},
    {"format_id": "134", "ext": "mp4", "height": 360, "vcodec": "avc1.4d401e", "acodec": "none", "filesize": 8388608},
    {"format_id": "136", "ext": "mp4", "height": 720, "vcodec": "avc1.4d401f", "acodec": "none", "filesize": 25165824},
    {"format_id": "137", "ext": "mp4", "height": 1080, "vcodec": "avc1.640028", "acodec": "none", "filesize": 91226112},
    {"format_id": "313", "ext": "webm", "height": 2160, "vcodec": "vp9", "acodec": "none", "filesize": 419430400}
  ]
}
```

- [ ] **Step 2: Write `Fixtures/playlist.json`**

```json
{
  "id": "PL1234",
  "_type": "playlist",
  "title": "Lecture Series",
  "uploader": "Some University",
  "entries": [
    {"id": "aaa", "title": "Lecture 1", "url": "https://youtu.be/aaa", "duration": 3600},
    {"id": "bbb", "title": "Lecture 2", "url": "https://youtu.be/bbb", "duration": 3400},
    {"id": "ccc", "title": "Lecture 3", "url": "https://youtu.be/ccc", "duration": 3500}
  ]
}
```

- [ ] **Step 3: Write the failing tests**

```swift
import Foundation
import Testing
@testable import YTDLPCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"))
    return try Data(contentsOf: url)
}

@Test func decodesSingleVideoMetadata() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))

    #expect(info.title == "Never Gonna Give You Up")
    #expect(info.uploader == "Rick Astley")
    #expect(info.duration == 213)
    #expect(info.thumbnailURL?.host == "i.ytimg.com")
    #expect(info.isPlaylist == false)
    #expect(info.entries.isEmpty)
    #expect(info.formats.count == 6)
}

@Test func decodesFormatFields() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))
    let format = try #require(info.formats.first { $0.formatID == "137" })

    #expect(format.height == 1080)
    #expect(format.vcodec == "avc1.640028")
    #expect(format.acodec == "none")
    #expect(format.filesize == 91_226_112)
}

@Test func audioOnlyFormatHasNoHeight() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))
    let format = try #require(info.formats.first { $0.formatID == "139" })

    #expect(format.height == nil)
    #expect(format.vcodec == "none")
}

@Test func decodesPlaylist() throws {
    let info = try MediaInfo.decode(from: fixture("playlist"))

    #expect(info.isPlaylist)
    #expect(info.title == "Lecture Series")
    #expect(info.entries.count == 3)
    #expect(info.entries[2].title == "Lecture 3")
    #expect(info.entries[0].url == "https://youtu.be/aaa")
    #expect(info.formats.isEmpty)
}

@Test func formattedDurationIsHumanReadable() throws {
    let info = try MediaInfo.decode(from: fixture("single-video"))
    #expect(info.formattedDuration == "3:33")
}

@Test func garbageInputThrows() {
    #expect(throws: (any Error).self) {
        try MediaInfo.decode(from: Data("not json".utf8))
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter MediaInfo`
Expected: FAIL, `cannot find 'MediaInfo' in scope`.

- [ ] **Step 5: Write the implementation**

```swift
import Foundation

public struct RawFormat: Equatable, Sendable, Decodable {
    public let formatID: String
    public let ext: String
    public let height: Int?
    public let vcodec: String?
    public let acodec: String?
    public let filesize: Int?

    private enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case ext, height, vcodec, acodec, filesize
    }

    /// yt-dlp writes the string "none" rather than omitting the codec.
    public var hasVideo: Bool { vcodec != nil && vcodec != "none" }
}

public struct PlaylistEntry: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let title: String
    public let url: String?
    public let duration: Double?
}

/// The decoded output of `yt-dlp -J`.
public struct MediaInfo: Equatable, Sendable, Decodable {
    public let title: String
    public let uploader: String?
    public let duration: Double?
    public let thumbnailURL: URL?
    public let formats: [RawFormat]
    public let entries: [PlaylistEntry]

    public var isPlaylist: Bool { !entries.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case title, uploader, duration, formats, entries
        case thumbnailURL = "thumbnail"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        uploader = try container.decodeIfPresent(String.self, forKey: .uploader)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        formats = try container.decodeIfPresent([RawFormat].self, forKey: .formats) ?? []
        entries = try container.decodeIfPresent([PlaylistEntry].self, forKey: .entries) ?? []
    }

    public static func decode(from data: Data) throws -> MediaInfo {
        try JSONDecoder().decode(MediaInfo.self, from: data)
    }

    /// "3:33", or "1:02:03" for anything an hour or longer.
    public var formattedDuration: String {
        guard let duration, duration > 0 else { return "" }
        let total = Int(duration.rounded())
        let (hours, minutes, seconds) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 46 tests.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: MediaInfo decoding with fixtures"
```

---

### Task 9: FormatCatalog

**Files:**
- Create: `YTDLPCore/Sources/YTDLPCore/FormatCatalog.swift`
- Test: `YTDLPCore/Tests/YTDLPCoreTests/FormatCatalogTests.swift`

**Interfaces:**
- Consumes: `RawFormat` (Task 8).
- Produces: `FormatChoice` (with `id`, `label`, `maxHeight`) and `FormatCatalog.choices(from:) -> [FormatChoice]`. Task 14's format menu is bound to this array; `maxHeight` feeds `MediaMode.video(maxHeight:)`.

The catalog deliberately reports heights rather than yt-dlp format ids, because ids can change between the probe and the download — the spec calls this out.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import YTDLPCore

private func videoFormat(height: Int, filesize: Int? = nil) -> RawFormat {
    let json = """
    {"format_id":"f\(height)","ext":"mp4","height":\(height),"vcodec":"avc1","acodec":"none"\
    \(filesize.map { ",\"filesize\":\($0)" } ?? "")}
    """
    return try! JSONDecoder().decode(RawFormat.self, from: Data(json.utf8))
}

private func audioFormat() -> RawFormat {
    let json = #"{"format_id":"139","ext":"m4a","vcodec":"none","acodec":"mp4a"}"#
    return try! JSONDecoder().decode(RawFormat.self, from: Data(json.utf8))
}

@Test func firstChoiceIsAlwaysBest() {
    let choices = FormatCatalog.choices(from: [videoFormat(height: 720)])
    #expect(choices.first?.id == "best")
    #expect(choices.first?.label == "Best")
    #expect(choices.first?.maxHeight == nil)
}

@Test func heightsAreListedHighestFirstWithoutDuplicates() {
    let formats = [
        videoFormat(height: 360), videoFormat(height: 1080),
        videoFormat(height: 720), videoFormat(height: 1080),
    ]
    #expect(FormatCatalog.choices(from: formats).map(\.maxHeight) == [nil, 1080, 720, 360])
}

@Test func audioOnlyFormatsAreExcluded() {
    let choices = FormatCatalog.choices(from: [audioFormat(), videoFormat(height: 480)])
    #expect(choices.map(\.maxHeight) == [nil, 480])
}

@Test func labelsUseFamiliarResolutionNames() {
    let formats = [2160, 1440, 1080, 720, 480].map { videoFormat(height: $0) }
    #expect(FormatCatalog.choices(from: formats).map(\.label)
            == ["Best", "4K", "1440p", "1080p", "720p", "480p"])
}

@Test func labelIncludesFilesizeWhenKnown() {
    let choices = FormatCatalog.choices(from: [videoFormat(height: 1080, filesize: 91_226_112)])
    #expect(choices[1].label == "1080p · 91 MB")
}

@Test func filesizeLabelIsLocaleIndependent() {
    // `ByteCountFormatter` renders "91,2 MB" in a German locale and "91.2 MB" in
    // a US one, so the catalog must not use it. This test fails if someone swaps
    // the deterministic formatter back out for the Foundation one.
    let choices = FormatCatalog.choices(from: [videoFormat(height: 720, filesize: 2_500_000_000)])
    #expect(choices[1].label == "720p · 2.5 GB")
}

@Test func audioOnlySourceOffersOnlyBest() {
    #expect(FormatCatalog.choices(from: [audioFormat()]).map(\.id) == ["best"])
}

@Test func noFormatsStillOffersBest() {
    #expect(FormatCatalog.choices(from: []).map(\.id) == ["best"])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test --filter FormatCatalog`
Expected: FAIL, `cannot find 'FormatCatalog' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct FormatChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// `nil` for "Best" — no height cap.
    public let maxHeight: Int?
}

/// Collapses yt-dlp's long format list into the handful of choices worth showing.
///
/// Reports heights rather than format ids, because ids can change between the
/// probe and the download.
public enum FormatCatalog {
    public static func choices(from formats: [RawFormat]) -> [FormatChoice] {
        let best = FormatChoice(id: "best", label: "Best", maxHeight: nil)

        var largestFilesize: [Int: Int] = [:]
        for format in formats where format.hasVideo {
            guard let height = format.height else { continue }
            largestFilesize[height] = max(largestFilesize[height] ?? 0, format.filesize ?? 0)
        }

        let rest = largestFilesize.keys.sorted(by: >).map { height in
            FormatChoice(
                id: String(height),
                label: label(height: height, filesize: largestFilesize[height] ?? 0),
                maxHeight: height
            )
        }
        return [best] + rest
    }

    private static func label(height: Int, filesize: Int) -> String {
        let name = height >= 2160 ? "4K" : "\(height)p"
        guard filesize > 0 else { return name }
        return "\(name) · \(humanSize(filesize))"
    }

    /// Deliberately not `ByteCountFormatter`: that renders "91,2 MB" in a German
    /// locale and "91.2 MB" in a US one, which would make the label untestable.
    /// Base 1000, matching what Finder reports.
    private static func humanSize(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / 1_000_000
        return megabytes >= 1000
            ? String(format: "%.1f GB", megabytes / 1000)
            : String(format: "%.0f MB", megabytes)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 54 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: FormatCatalog collapses yt-dlp formats to a short menu"
```

---

### Task 10: SystemProcessRunner

**Files:**
- Create: `YTDLP/Services/SystemProcessRunner.swift`

**Interfaces:**
- Consumes: `ProcessRunner`, `ProcessEvent` (Task 1).
- Produces: `SystemProcessRunner()`, the only production `ProcessRunner`. Tasks 11–13 depend on it.

This is the one piece the package can't hold and unit tests can't cover, so it is verified by running a real command. Cancelling the consuming task must send `SIGINT`, not `SIGKILL`, so yt-dlp deletes its own `.part` files.

- [ ] **Step 1: Write the implementation**

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/Developer/YTDLP && xcodebuild -project YTDLP.xcodeproj -scheme YTDLP -configuration Debug -derivedDataPath ./DD build 2>&1 | grep -E "^\*\*|error:"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify behaviour against a real process**

Temporarily replace the body of `ContentView` with the following, build, run, and read the Xcode console:

```swift
Text("probe").task {
    for await event in SystemProcessRunner().run(
        executable: "/bin/echo", arguments: ["hello", "world"]
    ) {
        print("EVENT:", event)
    }
}
```

Expected console output, in order:
```
EVENT: stdout("hello world")
EVENT: exit(code: 0)
```
Then restore `ContentView` to the placeholder from Task 1.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: SystemProcessRunner streams child process output"
```

---

### Task 11: BinaryManager

**Files:**
- Create: `YTDLP/Services/BinaryManager.swift`
- Create: `YTDLP/Resources/.gitkeep`

**Interfaces:**
- Consumes: `SystemProcessRunner` (Task 10).
- Produces: `BinaryManager.shared`, `.ytDlpPath: String`, `.ffmpegPath: String`, `.archivePath: String`, `.prepare() async throws`, `.checkForUpdates() async`. Tasks 12–13 read the paths; Task 15's Settings shows the version.

`yt-dlp -U` rewrites its own binary, which would invalidate the app's code signature if it ran inside the bundle — hence the copy into Application Support.

- [ ] **Step 1: Stage the binaries**

The binaries are gitignored (Task 1) because they are large and machine-specific. Copy the working ones in:

```bash
mkdir -p ~/Developer/YTDLP/YTDLP/Resources
cp /opt/homebrew/bin/yt-dlp ~/Developer/YTDLP/YTDLP/Resources/yt-dlp
cp /opt/homebrew/bin/ffmpeg ~/Developer/YTDLP/YTDLP/Resources/ffmpeg
chmod +x ~/Developer/YTDLP/YTDLP/Resources/{yt-dlp,ffmpeg}
touch ~/Developer/YTDLP/YTDLP/Resources/.gitkeep
```

Because `YTDLP/` is a synchronized folder group, both files are copied into the app bundle's `Contents/Resources/` automatically. No project file change.

- [ ] **Step 2: Write the implementation**

```swift
import Foundation
import YTDLPCore

/// Owns the locations of the yt-dlp and ffmpeg executables.
///
/// yt-dlp is copied out of the bundle into Application Support on first launch,
/// because `yt-dlp -U` rewrites its own binary and doing that inside the bundle
/// would invalidate the app's code signature. ffmpeg never self-updates and so
/// stays in the bundle.
@Observable
final class BinaryManager {
    static let shared = BinaryManager()

    private(set) var version: String = "unknown"

    private let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YTDLP", isDirectory: true)
    }()

    var ytDlpPath: String { supportDirectory.appendingPathComponent("bin/yt-dlp").path }
    var ffmpegPath: String { Bundle.main.path(forResource: "ffmpeg", ofType: nil) ?? "/opt/homebrew/bin/ffmpeg" }
    var archivePath: String { supportDirectory.appendingPathComponent("archive.txt").path }

    enum BinaryError: LocalizedError {
        case bundledCopyMissing

        var errorDescription: String? {
            "The bundled yt-dlp is missing — rebuild the app."
        }
    }

    /// Seeds or re-seeds the working copy, then records its version.
    /// Safe to call on every launch.
    func prepare() async throws {
        let fileManager = FileManager.default
        let binDirectory = supportDirectory.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        if !fileManager.isExecutableFile(atPath: ytDlpPath) {
            guard let bundled = Bundle.main.path(forResource: "yt-dlp", ofType: nil) else {
                throw BinaryError.bundledCopyMissing
            }
            if fileManager.fileExists(atPath: ytDlpPath) {
                try fileManager.removeItem(atPath: ytDlpPath)
            }
            try fileManager.copyItem(atPath: bundled, toPath: ytDlpPath)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytDlpPath)
        }

        version = await capture(arguments: ["--version"]) ?? "unknown"
    }

    /// Runs at most once a day. Failures are silent — a stale yt-dlp still works.
    func checkForUpdates() async {
        let key = "lastUpdateCheck"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        _ = await capture(arguments: ["--update-to", "stable"])
        version = await capture(arguments: ["--version"]) ?? version
    }

    private func capture(arguments: [String]) async -> String? {
        var output: [String] = []
        for await event in SystemProcessRunner().run(executable: ytDlpPath, arguments: arguments) {
            if case .stdout(let line) = event, !line.isEmpty { output.append(line) }
        }
        return output.last
    }
}
```

- [ ] **Step 3: Verify it compiles and seeds correctly**

Temporarily replace the body of `ContentView` with:

```swift
Text("prepare").task {
    try? await BinaryManager.shared.prepare()
    print("VERSION:", BinaryManager.shared.version)
    print("PATH:", BinaryManager.shared.ytDlpPath)
}
```

Run: build, launch, read the console.
Expected: a version like `2026.07.04`, and a path under `~/Library/Application Support/YTDLP/bin/yt-dlp`.

Confirm the copy exists:

```bash
ls -l ~/Library/Application\ Support/YTDLP/bin/yt-dlp
```

Then restore `ContentView` to the placeholder.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: BinaryManager seeds yt-dlp into Application Support"
```

---

### Task 12: MediaProbe

**Files:**
- Create: `YTDLP/Services/MediaProbe.swift`

**Interfaces:**
- Consumes: `ProcessRunner` (Task 1), `MediaInfo` (Task 8), `BinaryManager` (Task 11).
- Produces: `MediaProbe(runner:binaries:)`, `probe(url:) async throws -> MediaInfo`. Task 14's `ContentView` calls it after the debounce.

- [ ] **Step 1: Write the implementation**

```swift
import Foundation
import YTDLPCore

/// Fetches metadata for a URL without downloading it.
struct MediaProbe {
    var runner: any ProcessRunner = SystemProcessRunner()
    var binaries: BinaryManager = .shared

    struct ProbeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func probe(url: String) async throws -> MediaInfo {
        var stdout: [String] = []
        var stderr: [String] = []
        var exitCode: Int32 = -1

        let arguments = [
            "-J",
            "--no-warnings",
            "--flat-playlist",
            "--ffmpeg-location", binaries.ffmpegPath,
            url,
        ]

        for await event in runner.run(executable: binaries.ytDlpPath, arguments: arguments) {
            switch event {
            case .stdout(let line): stdout.append(line)
            case .stderr(let line): stderr.append(line)
            case .exit(let code): exitCode = code
            }
        }

        guard exitCode == 0 else {
            throw ProbeError(message: ErrorMapper.message(forStderr: stderr.joined(separator: "\n")))
        }
        return try MediaInfo.decode(from: Data(stdout.joined().utf8))
    }
}
```

`-J` prints one JSON document, but `--newline` splitting means it may arrive across several lines, so the parts are rejoined without separators.

- [ ] **Step 2: Verify against a real URL**

Temporarily replace the body of `ContentView` with:

```swift
Text("probe").task {
    try? await BinaryManager.shared.prepare()
    do {
        let info = try await MediaProbe().probe(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        print("TITLE:", info.title, "| DURATION:", info.formattedDuration, "| FORMATS:", info.formats.count)
    } catch {
        print("FAILED:", error.localizedDescription)
    }
}
```

Expected: a title, a duration like `3:33`, and a non-zero format count. This step needs a network connection; if the machine is offline, note it and move on — Task 16 re-verifies.

Then restore `ContentView` to the placeholder.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: MediaProbe fetches metadata via yt-dlp -J"
```

---

### Task 13: AppSettings and DownloadQueue

**Files:**
- Create: `YTDLP/Model/AppSettings.swift`
- Create: `YTDLP/Model/DownloadQueue.swift`

**Interfaces:**
- Consumes: `DownloadOptions`, `OptionResolver`, `ArgumentBuilder`, `ProgressParser`, `ErrorMapper` (Tasks 2–7), `BinaryManager` (Task 11).
- Produces: `AppSettings.shared` with `.downloadFolder`, `.sponsorBlockCategories`, `.preferAppleCodecs`, `.concurrentFragments`, `.defaultAudioFormat`, `.subtitleLanguages`, `.cookieBrowser`, and `.makeOptions(mode:isPlaylist:clip:subtitlesEnabled:cookiesEnabled:) -> DownloadOptions`; `DownloadQueue.shared` with `.jobs`, `.start(url:options:title:)`, `.cancel(_:)`. Tasks 14–16 bind to these.

- [ ] **Step 1: Write `AppSettings.swift`**

```swift
import Foundation
import SwiftUI
import YTDLPCore

/// Persisted preferences, and the single place a `DownloadOptions` is assembled
/// from settings plus the drawer's per-download choices.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var downloadFolder: String {
        didSet { UserDefaults.standard.set(downloadFolder, forKey: "downloadFolder") }
    }
    var sponsorBlockCategories: [String] {
        didSet { UserDefaults.standard.set(sponsorBlockCategories, forKey: "sponsorBlockCategories") }
    }
    var preferAppleCodecs: Bool {
        didSet { UserDefaults.standard.set(preferAppleCodecs, forKey: "preferAppleCodecs") }
    }
    var concurrentFragments: Int {
        didSet { UserDefaults.standard.set(concurrentFragments, forKey: "concurrentFragments") }
    }
    var defaultAudioFormat: AudioFormat {
        didSet { UserDefaults.standard.set(defaultAudioFormat.rawValue, forKey: "defaultAudioFormat") }
    }
    var subtitleLanguages: String {
        didSet { UserDefaults.standard.set(subtitleLanguages, forKey: "subtitleLanguages") }
    }
    var cookieBrowser: String {
        didSet { UserDefaults.standard.set(cookieBrowser, forKey: "cookieBrowser") }
    }

    static let availableSponsorBlockCategories = ["sponsor", "selfpromo", "intro", "outro", "interaction", "music_offtopic"]
    static let availableCookieBrowsers = ["safari", "chrome", "firefox", "edge", "brave"]

    private init() {
        let defaults = UserDefaults.standard
        downloadFolder = defaults.string(forKey: "downloadFolder")
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        sponsorBlockCategories = defaults.stringArray(forKey: "sponsorBlockCategories") ?? ["sponsor"]
        preferAppleCodecs = defaults.object(forKey: "preferAppleCodecs") as? Bool ?? true
        concurrentFragments = defaults.object(forKey: "concurrentFragments") as? Int ?? 4
        defaultAudioFormat = AudioFormat(rawValue: defaults.string(forKey: "defaultAudioFormat") ?? "") ?? .m4a
        subtitleLanguages = defaults.string(forKey: "subtitleLanguages") ?? "en"
        cookieBrowser = defaults.string(forKey: "cookieBrowser") ?? "safari"
    }

    func makeOptions(
        mode: MediaMode,
        isPlaylist: Bool,
        clip: TimeRange?,
        subtitlesEnabled: Bool,
        cookiesEnabled: Bool
    ) -> DownloadOptions {
        let languages = subtitleLanguages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return DownloadOptions(
            mode: mode,
            isPlaylist: isPlaylist,
            clip: clip,
            subtitleLanguages: subtitlesEnabled ? languages : nil,
            cookieBrowser: cookiesEnabled ? cookieBrowser : nil,
            sponsorBlockCategories: sponsorBlockCategories,
            preferAppleCodecs: preferAppleCodecs,
            concurrentFragments: concurrentFragments,
            downloadFolder: downloadFolder,
            ffmpegPath: BinaryManager.shared.ffmpegPath,
            archivePath: BinaryManager.shared.archivePath
        )
    }
}
```

- [ ] **Step 2: Write `DownloadQueue.swift`**

```swift
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
        jobs.append(job)

        let resolved = OptionResolver.resolve(options)
        let arguments = ArgumentBuilder.argv(url: url, options: resolved)
        let executable = binaries.ytDlpPath

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

        for await event in runner.run(executable: executable, arguments: arguments) {
            switch event {
            case .stdout(let line):
                guard let progress = ProgressParser.parse(line) else { continue }
                await apply(progress, to: job)

            case .stderr(let line):
                stderr.append(line)
                if let progress = ProgressParser.parse(line) {
                    await apply(progress, to: job)
                }

            case .exit(let code):
                await MainActor.run {
                    if code == 0 {
                        job.state = .finished
                        self.onFinished?(job)
                    } else {
                        let raw = stderr.joined(separator: "\n")
                        job.state = .failed(message: ErrorMapper.message(forStderr: raw), details: raw)
                    }
                    self.tasks[job.id] = nil
                }
            }
        }
    }

    @MainActor
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
```

- [ ] **Step 3: Verify it compiles**

Run: `cd ~/Developer/YTDLP && xcodebuild -project YTDLP.xcodeproj -scheme YTDLP -configuration Debug -derivedDataPath ./DD build 2>&1 | grep -E "^\*\*|error:"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: AppSettings and DownloadQueue"
```

---

### Task 14: The main window

**Files:**
- Create: `YTDLP/Views/MetadataCard.swift`, `YTDLP/Views/OptionsDrawer.swift`, `YTDLP/Views/QueueList.swift`
- Modify: `YTDLP/ContentView.swift` (replace the Task 1 placeholder entirely)
- Modify: `YTDLP/YTDLPApp.swift`

**Interfaces:**
- Consumes: everything from Tasks 8–13.
- Produces: the running UI. Task 15 adds the Settings scene; Task 16 adds notifications and clipboard detection.

- [ ] **Step 1: Write `MetadataCard.swift`**

```swift
import SwiftUI
import YTDLPCore

struct MetadataCard: View {
    let info: MediaInfo

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: info.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(2)
                Text([info.uploader, info.formattedDuration.isEmpty ? nil : info.formattedDuration]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Step 2: Write `OptionsDrawer.swift`**

```swift
import SwiftUI
import YTDLPCore

struct OptionsDrawer: View {
    @Binding var audioOnly: Bool
    @Binding var audioFormat: AudioFormat
    @Binding var subtitlesEnabled: Bool
    @Binding var cookiesEnabled: Bool
    @Binding var clipEnabled: Bool
    @Binding var clipStart: String
    @Binding var clipEnd: String

    let isPlaylist: Bool
    let notices: [OptionNotice]
    let cookieBrowser: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Audio only", isOn: $audioOnly)
            if audioOnly {
                Picker("Format", selection: $audioFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Subtitles", isOn: $subtitlesEnabled)
                .disabled(audioOnly)

            Toggle("Use \(cookieBrowser.capitalized) cookies", isOn: $cookiesEnabled)

            Toggle("Clip", isOn: $clipEnabled)
                .disabled(isPlaylist)
            if clipEnabled, !isPlaylist {
                HStack(spacing: 6) {
                    TextField("00:00:00", text: $clipStart).frame(width: 80)
                    Text("–").foregroundStyle(.secondary)
                    TextField("00:00:00", text: $clipEnd).frame(width: 80)
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }

            ForEach(notices, id: \.self) { notice in
                Label(notice.message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}
```

- [ ] **Step 3: Write `QueueList.swift`**

```swift
import SwiftUI

struct QueueList: View {
    let jobs: [DownloadJob]
    let onCancel: (DownloadJob) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(jobs) { job in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title).font(.callout).lineLimit(1)
                            statusLine(for: job)
                        }
                        Spacer(minLength: 0)
                        Button {
                            onCancel(job)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
    }

    @ViewBuilder
    private func statusLine(for job: DownloadJob) -> some View {
        switch job.state {
        case .waiting:
            Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .downloading(let percent, let speed, let eta):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: percent, total: 100)
                Text("\(speed) · \(eta) left").font(.caption).foregroundStyle(.secondary)
            }
        case .processing(let label):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView().progressViewStyle(.linear)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        case .retrying:
            Text("Retrying…").font(.caption).foregroundStyle(.secondary)
        case .finished:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message, _):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }
}
```

- [ ] **Step 4: Replace `ContentView.swift`**

```swift
import SwiftUI
import YTDLPCore

struct ContentView: View {
    @State private var settings = AppSettings.shared
    @State private var queue = DownloadQueue.shared

    @State private var urlText = ""
    @State private var info: MediaInfo?
    @State private var probeError: String?
    @State private var isProbing = false
    @State private var probeTask: Task<Void, Never>?

    @State private var choices: [FormatChoice] = []
    @State private var selectedHeight: Int?

    @State private var showOptions = false
    @State private var audioOnly = false
    @State private var audioFormat: AudioFormat = .m4a
    @State private var subtitlesEnabled = false
    @State private var cookiesEnabled = false
    @State private var clipEnabled = false
    @State private var clipStart = "00:00:00"
    @State private var clipEnd = "00:00:00"

    private var draftOptions: DownloadOptions {
        settings.makeOptions(
            mode: audioOnly ? .audio(format: audioFormat) : .video(maxHeight: selectedHeight),
            isPlaylist: info?.isPlaylist ?? false,
            clip: clipEnabled ? TimeRange(start: clipStart, end: clipEnd) : nil,
            subtitlesEnabled: subtitlesEnabled,
            cookiesEnabled: cookiesEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Paste a video URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .onSubmit(startDownload)
                .onChange(of: urlText) { _, new in scheduleProbe(for: new) }

            if isProbing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading…").foregroundStyle(.secondary)
                }
            } else if let info {
                MetadataCard(info: info)
            } else if let probeError {
                Label(probeError, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if !queue.jobs.isEmpty {
                Divider()
                QueueList(jobs: queue.jobs) { queue.cancel($0) }
            }

            HStack(spacing: 10) {
                Picker("", selection: $selectedHeight) {
                    ForEach(choices) { choice in
                        Text(choice.label).tag(choice.maxHeight)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                .disabled(audioOnly || choices.count <= 1)

                Button(showOptions ? "Options ⌄" : "Options ›") {
                    withAnimation(.snappy(duration: 0.15)) { showOptions.toggle() }
                }
                .buttonStyle(.link)

                Spacer()

                Button("Download", action: startDownload)
                    .keyboardShortcut(.defaultAction)
                    .disabled(info == nil)
            }

            if showOptions {
                Divider()
                OptionsDrawer(
                    audioOnly: $audioOnly,
                    audioFormat: $audioFormat,
                    subtitlesEnabled: $subtitlesEnabled,
                    cookiesEnabled: $cookiesEnabled,
                    clipEnabled: $clipEnabled,
                    clipStart: $clipStart,
                    clipEnd: $clipEnd,
                    isPlaylist: info?.isPlaylist ?? false,
                    notices: OptionResolver.resolve(draftOptions).notices,
                    cookieBrowser: settings.cookieBrowser
                )
            }
        }
        .padding(16)
        .frame(width: 460)
        .task {
            try? await BinaryManager.shared.prepare()
            await BinaryManager.shared.checkForUpdates()
        }
    }

    private func scheduleProbe(for text: String) {
        probeTask?.cancel()
        info = nil
        probeError = nil
        choices = []
        selectedHeight = nil

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else {
            isProbing = false
            return
        }

        isProbing = true
        probeTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let probed = try await MediaProbe().probe(url: trimmed)
                guard !Task.isCancelled else { return }
                info = probed
                choices = FormatCatalog.choices(from: probed.formats)
                selectedHeight = choices.first(where: { $0.maxHeight == 1080 })?.maxHeight
                    ?? choices.first?.maxHeight
                audioFormat = settings.defaultAudioFormat
            } catch {
                guard !Task.isCancelled else { return }
                probeError = error.localizedDescription
            }
            isProbing = false
        }
    }

    private func startDownload() {
        guard let info else { return }
        queue.start(
            url: urlText.trimmingCharacters(in: .whitespacesAndNewlines),
            options: draftOptions,
            title: info.title
        )
        resetDrawer()
    }

    /// Per-download options do not carry over, per the spec.
    private func resetDrawer() {
        urlText = ""
        self.info = nil
        choices = []
        selectedHeight = nil
        audioOnly = false
        subtitlesEnabled = false
        cookiesEnabled = false
        clipEnabled = false
        clipStart = "00:00:00"
        clipEnd = "00:00:00"
        showOptions = false
    }
}
```

- [ ] **Step 5: Build and exercise the window**

Run: `cd ~/Developer/YTDLP && xcodebuild -project YTDLP.xcodeproj -scheme YTDLP -configuration Debug -derivedDataPath ./DD build 2>&1 | grep -E "^\*\*|error:"`
Expected: `** BUILD SUCCEEDED **`.

Then `open ./DD/Build/Products/Debug/YTDLP.app` and confirm, in order:
1. The window is a single URL field with a disabled Download button.
2. Pasting a YouTube URL shows "Reading…", then a thumbnail, title, uploader, and duration.
3. The format menu lists real resolutions for that video, defaulting to 1080p.
4. Clicking Options expands the drawer; ticking Audio only disables the Subtitles checkbox and the format menu.
5. Ticking Clip and setting a range shows the notice "Sponsor removal is off while clipping."
6. Download starts a queue row with a moving progress bar, a speed, and an ETA — and no Terminal window opens.
7. The finished file is in `~/Downloads`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: main window with metadata, format picker, options drawer, and queue"
```

---

### Task 15: Settings window

**Files:**
- Create: `YTDLP/Views/SettingsView.swift`
- Modify: `YTDLP/YTDLPApp.swift`

**Interfaces:**
- Consumes: `AppSettings` (Task 13), `BinaryManager` (Task 11).
- Produces: the `Settings` scene, reachable with ⌘,.

- [ ] **Step 1: Write `SettingsView.swift`**

```swift
import SwiftUI
import YTDLPCore

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var binaries = BinaryManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(settings.downloadFolder)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }
            } header: {
                Text("Save to")
            }

            Section {
                ForEach(AppSettings.availableSponsorBlockCategories, id: \.self) { category in
                    Toggle(category.replacingOccurrences(of: "_", with: " ").capitalized, isOn: binding(for: category))
                }
            } header: {
                Text("Remove segments")
            }

            Section {
                Toggle("Prefer H.264 / AAC", isOn: $settings.preferAppleCodecs)
                Text("Plays natively in QuickTime and on Apple TV. Turn off for smaller files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper("Parallel fragments: \(settings.concurrentFragments)",
                        value: $settings.concurrentFragments, in: 1...16)

                Picker("Audio format", selection: $settings.defaultAudioFormat) {
                    ForEach(AudioFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }

                TextField("Subtitle languages", text: $settings.subtitleLanguages)

                Picker("Cookies from", selection: $settings.cookieBrowser) {
                    ForEach(AppSettings.availableCookieBrowsers, id: \.self) { Text($0.capitalized).tag($0) }
                }
            } header: {
                Text("Downloads")
            }

            Section {
                LabeledContent("yt-dlp", value: binaries.version)
                Button("Check for updates") {
                    UserDefaults.standard.removeObject(forKey: "lastUpdateCheck")
                    Task { await binaries.checkForUpdates() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding(for category: String) -> Binding<Bool> {
        Binding(
            get: { settings.sponsorBlockCategories.contains(category) },
            set: { isOn in
                if isOn {
                    if !settings.sponsorBlockCategories.contains(category) {
                        settings.sponsorBlockCategories.append(category)
                    }
                } else {
                    settings.sponsorBlockCategories.removeAll { $0 == category }
                }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolder = url.path
        }
    }
}
```

- [ ] **Step 2: Add the Settings scene to `YTDLPApp.swift`**

```swift
import SwiftUI

@main
struct YTDLPApp: App {
    var body: some Scene {
        Window("yt-dlp", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Build, launch, press ⌘, and confirm: the folder picker changes the save location, ticking SponsorBlock categories persists across a relaunch, and the yt-dlp version is shown.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: Settings window"
```

---

### Task 16: Notifications, Finder reveal, and clipboard detection

**Files:**
- Create: `YTDLP/Services/Notifier.swift`
- Modify: `YTDLP/ContentView.swift`

**Interfaces:**
- Consumes: `DownloadQueue` (Task 13), `AppSettings` (Task 13).
- Produces: `Notifier.shared.requestAuthorization()`, `.notifyFinished(title:folder:)`. Completes the app.

- [ ] **Step 1: Write `Notifier.swift`**

```swift
import AppKit
import Foundation
import UserNotifications

/// Completion notifications, plus revealing the finished file in Finder.
final class Notifier {
    static let shared = Notifier()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyFinished(title: String, folder: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download finished"
        content.body = title
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    func reveal(folder: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }
}
```

Notification actions are deliberately omitted: wiring "Reveal in Finder" into a notification button requires a `UNUserNotificationCenterDelegate` and knowledge of the final filename, which yt-dlp only reports in its `[download] Destination:` line. The queue row's own controls cover the same need. If you later want the button, parse `Destination:` in `ProgressParser` first.

- [ ] **Step 2: Wire it into `ContentView`**

Replace the `.task { … }` modifier on the outer `VStack` with:

```swift
.task {
    Notifier.shared.requestAuthorization()
    queue.onFinished = { job in
        Notifier.shared.notifyFinished(title: job.title, folder: settings.downloadFolder)
    }
    try? await BinaryManager.shared.prepare()
    await BinaryManager.shared.checkForUpdates()
}
.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
    adoptClipboardURL()
}
```

Add these members to `ContentView`:

```swift
@State private var lastClipboardURL = ""

/// Prefills the field from the clipboard, but never overwrites typed text.
private func adoptClipboardURL() {
    guard urlText.isEmpty else { return }
    guard let pasted = NSPasteboard.general.string(forType: .string) else { return }

    let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("http"), trimmed != lastClipboardURL else { return }

    lastClipboardURL = trimmed
    urlText = trimmed
}
```

Add `import AppKit` at the top of `ContentView.swift`.

- [ ] **Step 3: Add a Reveal button to finished queue rows**

In `QueueList.swift`, change the `.finished` case of `statusLine(for:)` to:

```swift
case .finished:
    HStack(spacing: 6) {
        Label("Done", systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(.green)
        Button("Show in Finder") {
            Notifier.shared.reveal(folder: AppSettings.shared.downloadFolder)
        }
        .buttonStyle(.link)
        .font(.caption)
    }
```

- [ ] **Step 4: Build and verify the whole flow**

Build and launch, then confirm:
1. Copy a YouTube URL in Safari, switch to the app — the field fills in and probing starts.
2. Type a URL by hand, switch away and back — your text is not replaced.
3. A completed download posts a notification and shows a working "Show in Finder" button.
4. Cancelling mid-download leaves no `.part` files: `ls ~/Downloads/*.part` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: notifications, Finder reveal, and clipboard detection"
```

---

### Task 17: Drag and drop, dock progress, and finished-job cleanup

**Files:**
- Modify: `YTDLP/Model/DownloadQueue.swift`
- Modify: `YTDLP/ContentView.swift`
- Modify: `YTDLP/YTDLPApp.swift`

**Interfaces:**
- Consumes: `DownloadQueue` (Task 13), `Notifier` (Task 16).
- Produces: no new public symbols. Completes the three remaining spec requirements — dropping a link, the dock tile progress bar, and the Done state clearing itself after 8 seconds.

- [ ] **Step 1: Auto-remove finished jobs and drive the dock tile**

Add to `DownloadQueue`, and call `updateDockTile()` at the end of both `apply(_:to:)` and the `.exit` branch of `execute(job:executable:arguments:)`:

```swift
/// Aggregate progress across active jobs, or `nil` when nothing is running.
private var aggregateProgress: Double? {
    let active = jobs.compactMap { job -> Double? in
        if case .downloading(let percent, _, _) = job.state { return percent }
        if case .processing = job.state { return 100 }
        return nil
    }
    guard !active.isEmpty else { return nil }
    return active.reduce(0, +) / Double(active.count)
}

@MainActor
private func updateDockTile() {
    let tile = NSApp.dockTile
    if let progress = aggregateProgress {
        tile.badgeLabel = "\(Int(progress))%"
    } else {
        tile.badgeLabel = nil
    }
    tile.display()
}

/// The spec's "Done" state clears itself; this is that, per row.
@MainActor
private func scheduleCleanup(of job: DownloadJob) {
    Task {
        try? await Task.sleep(for: .seconds(8))
        guard case .finished = job.state else { return }
        self.remove(job)
        self.updateDockTile()
    }
}
```

In the `.exit` branch, immediately after `job.state = .finished` and the `onFinished` call, add `self.scheduleCleanup(of: job)`. Add `import AppKit` at the top of the file.

Failed jobs are deliberately left in place — an error the user never saw is worse than a stale row.

- [ ] **Step 2: Accept dropped links on the window**

In `ContentView`, add this modifier to the outer `VStack`, directly after `.frame(width: 460)`:

```swift
.dropDestination(for: URL.self) { urls, _ in
    guard let dropped = urls.first, dropped.scheme?.hasPrefix("http") == true else { return false }
    urlText = dropped.absoluteString
    return true
}
```

- [ ] **Step 3: Accept links dropped on the dock icon**

Add an app delegate to `YTDLPApp.swift`:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ContentView so a dock drop can reach the URL field.
    static var openURLHandler: ((String) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        AppDelegate.openURLHandler?(first.absoluteString)
    }
}

@main
struct YTDLPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("yt-dlp", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
```

Then register the handler inside `ContentView`'s existing `.task { … }`, as its first line:

```swift
AppDelegate.openURLHandler = { urlText = $0 }
```

- [ ] **Step 4: Build and verify all three**

Build and launch, then confirm:
1. Dragging a link from Safari onto the window fills the URL field and starts probing.
2. Dragging a link onto the dock icon does the same.
3. During a download the dock icon shows a percentage badge, which clears when the queue empties.
4. A finished row disappears on its own about 8 seconds later; a failed row stays.

- [ ] **Step 5: Full regression**

Run: `cd ~/Developer/YTDLP/YTDLPCore && swift test`
Expected: PASS, 54 tests.

Run: `cd ~/Developer/YTDLP && xcodebuild -project YTDLP.xcodeproj -scheme YTDLP -configuration Debug -derivedDataPath ./DD build 2>&1 | grep -E "^\*\*|error:"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Install it**

```bash
cp -R ~/Developer/YTDLP/DD/Build/Products/Debug/YTDLP.app /Applications/
open /Applications/YTDLP.app
```

The old AppleScript applet at `/Users/oleheinrichs/Applications/yt-dlp/yt-dlp.app` is untouched. Delete it once you're happy with the replacement.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: drag and drop, dock progress, finished-job cleanup"
```

---

## Verification Summary

| What | Command | Expected |
|---|---|---|
| Core logic | `cd YTDLPCore && swift test` | 54 tests pass |
| App builds | `xcodebuild -project YTDLP.xcodeproj -scheme YTDLP -configuration Debug -derivedDataPath ./DD build` | `** BUILD SUCCEEDED **` |
| Main flow | Task 14, Step 5 | All seven checks pass |
| Integration | Task 16 Step 4 and Task 17 Step 4 | All eight checks pass |

## Known divergences from the spec

Two deliberate, both recorded here so a reviewer doesn't treat them as omissions:

1. **Notification action buttons.** The spec describes "Reveal in Finder" and "Play" buttons on the completion notification. The notification carries no buttons; the queue row does instead. Adding them needs a `UNUserNotificationCenterDelegate` plus the final filename, which yt-dlp only reports in its `[download] Destination:` line — so it needs a `ProgressParser` change first. Task 16, Step 1 says the same.
2. **Format menu labels.** The spec's mockup reads "1080p H.264"; the built menu reads "1080p · 91 MB". The codec is a global preference rather than a per-format choice, so repeating it on every row would be noise, and filesize is the more useful number when picking.
