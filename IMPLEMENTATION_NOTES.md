# WorkBench Implementation Notes

This document records implementation details and discoveries that may evolve as the MVP is built. The stable product vision remains in `docs/WorkBench_MVP_Design_Specification.md`.

## Baseline

- Xcode: 26.6 (build 17F113)
- macOS SDK: 26.5
- Swift: 6.3.3
- Deployment target: macOS 26.0
- UI framework: SwiftUI
- Swift language mode: Swift 6
- Strict concurrency checking: complete
- Default actor isolation: Main Actor for the application target
- App Sandbox: enabled
- Hardened Runtime: enabled
- Dependencies: none
- Provisional bundle identifier: `com.example.WorkBench`

The bundle identifier must be replaced with an appropriate reverse-DNS identifier before signing or distribution.

## Targets

- `WorkBench`: native macOS application
- `WorkBenchTests`: hosted unit-test bundle

Generated Info.plist files are used for both targets. The checked-in entitlements enable App Sandbox, user-selected read/write access, app-scoped bookmarks, Apple Events Automation, and temporary Apple Event exceptions limited to Safari, Terminal, and Finder, as established by the Phase 1 spikes.

## Verification

The baseline application and test suite pass with:

```bash
xcodebuild test \
  -project WorkBench.xcodeproj \
  -scheme WorkBench \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WorkBenchDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

The initial sandboxed command-line run could not start Xcode's Swift macro service for the SwiftUI preview. Running Xcode with normal system access resolved that environment restriction. The build also reports that App Intents metadata extraction is skipped because WorkBench does not link App Intents; this is expected for the baseline.

## Phase 1 filesystem spike

Apple's current App Sandbox model does not provide an entitlement granting automatic access to the user's Documents folder. A sandboxed app has unrestricted access to its own container and can request fixed access to certain standard media folders and Downloads, but access to another folder must originate from an explicit user selection.

The supported approach for keeping configurations at `~/Documents/WorkBench` is therefore:

1. On first run, present a standard folder-selection panel initially pointing at `~/Documents`.
2. Ask the user to select an existing `WorkBench` folder or create and select it through the system panel.
3. Enable user-selected read/write access and app-scoped bookmarks.
4. Save a security-scoped bookmark in application preferences.
5. Resolve the bookmark and balance `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()` whenever the repository is used.
6. If the bookmark is missing, stale, or denied, request folder access again without hiding or replacing existing configurations.

This product-flow change from automatic, silent directory creation was approved and implemented. No temporary-exception or broad filesystem entitlement is used.

The signed debug app was verified with App Sandbox, user-selected read/write access, and app-scoped bookmark entitlements. After the user selected `~/Documents/WorkBench`, WorkBench persisted the bookmark and restored access in a separately launched app instance. Both selection and restoration perform a reversible atomic write/read/delete probe, balance security-scoped resource access, and leave no probe file behind.

## Phase 1 Automation spike

The first signed Automation run used the hardened-runtime Apple Events entitlement and the required usage description. Safari, Terminal, and Finder each returned `Application isn't running`, including Finder, which was already running. Inspection of their scripting definitions found no public scripting access groups that cover WorkBench's required operations.

The approved sandbox configuration therefore includes `com.apple.security.temporary-exception.apple-events` entries limited to:

- `com.apple.Safari`
- `com.apple.Terminal`
- `com.apple.finder`

The general Apple Events entitlement allows macOS to request user consent, while these sandbox exceptions permit events only to the named applications. This may require justification during a future Mac App Store review and must be reassessed before distribution. It does not permit arbitrary application automation.

The final signed spike succeeded for all three applications:

- Safari created a new window with `https://apple.com` and `https://ibm.com` in separate tabs. Safari exposes the tab collection through its window object, not the document returned when creating the window.
- Terminal created a new window and changed its directory to the user's home directory.
- Finder created a new window showing the user's home directory.

The spike runner attempts adapters sequentially and records each outcome independently. Automated coverage verifies ordering and that a failure does not prevent later adapters from running.

## Phase 2 domain model and schema

Schema version 1 is implemented with:

- UUID-backed `ProjectID` and `ResourceID` value types encoded as JSON strings;
- stable lowercase UUID filenames independent of friendly Project names;
- ordered Browser Window, Terminal Session, and Finder Window Resources;
- a local `JSONValue` representation for lossless semantic preservation of unsupported Resource objects;
- explicit rejection of unsupported Project schema versions;
- validation for required names, unique Project names and identifiers, Resource identifiers, Safari URLs, and path syntax;
- absolute and `~`-relative path support with deterministic expansion; and
- a canonical Starter Project factory.

Unknown Resource types remain valid, retain their complete JSON objects, and can round-trip without losing nested values or large JSON numbers. Known Resource types are strongly typed. The model does not depend on SwiftUI, Apple Events, or filesystem persistence.

## Phase 3 Project repository

The Project repository is implemented behind injected directory, initialization-state, and atomic-writer interfaces. Production operations use the selected configuration directory's security-scoped access, while tests use isolated temporary directories.

Repository behavior includes:

- deterministic discovery of JSON files and sorting of valid Projects by friendly name;
- file-specific visible issues for malformed JSON, invalid Projects, duplicate names, and filenames that do not match the Project's stable UUID filename;
- atomic Project saves with validation and case-insensitive unique-name enforcement;
- Starter Project creation only on the first successful load of a genuinely uninitialized empty repository;
- a durable initialization marker written only after the Starter Project file is saved successfully;
- deletion of only the requested stable-identifier file, with confirmation remaining the responsibility of the later workflow layer; and
- semantic preservation of unsupported Resource JSON across repository load and save.

Repository calls are currently synchronous and main-actor isolated, matching the small local JSON files expected for the MVP. Responsiveness must be reviewed when the repository is connected to the interface; file work should move off the main actor if measurements show noticeable blocking.

## Phase 4 draft-editing workflows

`ProjectWorkflow` is the main-actor application-state boundary between the future SwiftUI interface and `ProjectRepository`. It keeps the persisted Project and active draft as separate values and derives dirty state through value comparison.

Selection, configuration reload, window close, quit, creation, duplication, and deletion all enter through one action request path. When the draft is dirty, the action is retained until the interface supplies Save, Discard, or Cancel:

- Save persists and validates the draft before continuing the retained action.
- Discard restores the persisted value, or abandons a new unsaved Project, before continuing.
- Cancel clears the retained action and leaves the draft and selection unchanged.
- A failed Save retains the draft, selection, dirty state, and pending action so the user can correct the problem or choose again.

New and duplicated Projects remain drafts until explicitly saved. Duplicates receive new Project and Resource identifiers and a deterministic unique friendly name. Resource additions, removals, edits, and ordering changes use the same draft mutation boundary and are persisted only by Save. Deletion is executed only after the caller requests it; the confirmation dialog remains a Phase 5 presentation responsibility.

## Phase 5 core SwiftUI interface

The spike screen has been replaced by a conventional single-window macOS editor built with `NavigationSplitView`:

- the Projects column shows valid Projects and file-specific configuration issues;
- the Resources column shows the ordered draft Resources, supports reordering, and provides supported Resource creation and removal controls; and
- the Properties column edits the Project or selected Resource, shows dirty state and contextual validation, and distinguishes unsupported Resources while explaining that their JSON is preserved.

`WorkBenchApplicationModel` owns presentation coordination without moving filesystem calls into views. It connects folder selection, repository startup, draft commands, error presentation, deletion confirmation, and unsaved-change choices. Window close and standard application termination use the same workflow decisions as Project selection and Reload Configurations.

The application uses a SwiftUI `Window` scene rather than a multi-window group. Save and Reload Configurations are standard menu commands; Reload uses Command-Shift-R. No status-bar item is created. Project launching is intentionally absent from this phase and will connect to the proven Automation adapters through the Phase 6 launch coordinator.

Xcode 26.6's Swift compiler crashed during IR generation for a direct method-reference conversion used as a `Binding<ProjectID?>` setter. An equivalent explicit closure avoids the compiler defect. The initial restricted command-line build also could not run the Swift Observation macro service; normal Xcode build access is required, as already observed for SwiftUI macros in the baseline.

## Phase 6 Resource launch coordination

The hard-coded Automation spike runner was replaced by the production `ProjectLauncher` and removed. The launcher validates the complete draft before opening anything, then processes Resources sequentially in their displayed order through `BrowserLaunching`, `TerminalLaunching`, and `FinderLaunching` boundaries.

Production behavior includes:

- a new Safari window with all configured URLs in order;
- a new Terminal window whose shell changes to the resolved working directory;
- a new Finder window showing the resolved folder;
- launch-time existence and directory checks for Terminal and Finder paths;
- AppleScript string escaping for user-controlled URLs and paths;
- unsupported Resources recorded as skipped without preventing known Resources from opening;
- adapter failures recorded without preventing later Resources from opening; and
- a consolidated sheet containing validation errors, failures, skipped Resources, and successful attempts whenever the Project does not open completely.

`LaunchReport` and per-Resource results are values independent of SwiftUI. Automated tests cover validation short-circuiting, exact adapter order, continuation after failure, unsupported types, missing paths, parameterized script construction, and application-model report presentation.

The adapters currently execute `NSAppleScript` synchronously on the main actor because that API and the existing verified permission behavior are main-thread-oriented. The small MVP launch sequence is bounded, but responsiveness should be measured during hardening; a safe off-main execution strategy should be adopted if real launches visibly block the editor.

An ad-hoc signed sandboxed build succeeds with the approved app-scoped bookmark and targeted Safari, Terminal, and Finder Apple Event entitlements. The production UI successfully opened the real Starter Project in all three applications with no launch errors.

The first production integration run opened all three applications, but revealed that `FileManager.homeDirectoryForCurrentUser` resolves to the application container while WorkBench is sandboxed. As a result, `~/` initially expanded to `~/Library/Containers/com.example.WorkBench/Data`. Path expansion now reads the login account home from the POSIX password database and falls back to Foundation's named-user lookup. Terminal and Finder therefore resolve `~/` to the actual user home while configuration storage remains sandbox-scoped.

The Terminal adapter initially activated Terminal before sending its `do script` command. During manual verification, a newly created Terminal session appeared to receive the home-directory `cd` twice. The adapter now creates the scripted session before activating Terminal, and automated coverage verifies that ordering. A signed-build retest initially showed a single `cd`, but a later repeated Project launch displayed it twice again. The final directory remained correct, so this is currently an intermittent cosmetic limitation rather than a launch failure. WorkBench retains the explicit directory change for predictable behavior when shell profiles customize their initial directory.

Repeated Project opening was manually verified by comparing application window counts before and after another launch. Safari, Terminal, and Finder each gained exactly one window, confirming that WorkBench does not reuse the previously opened workspace windows. Permission-denial recovery has not yet been manually verified.

## Resource removal crash fix

Manual hardening found a crash when a newly added Browser Window was selected and immediately removed. The outgoing SwiftUI property editor reevaluated a binding that captured the Resource's former array index after the Resource had been deleted, causing an out-of-bounds subscript trap.

Resource property bindings and tab actions now use the stable `ResourceID` to find the current array position at access time. Missing Resources and stale tab positions safely return or no-op, and selection is cleared before removal mutates the draft. The full automated suite passes, and the original add-select-remove sequence was repeated successfully in a signed build without a crash.
