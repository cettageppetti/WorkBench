# WorkBench Implementation Notes

This document records implementation details and discoveries that may evolve as the MVP is built. The stable product vision remains in `docs/WorkBench_MVP_Design_Specification.md`.

## Application-managed Project library

WorkBench now owns its live Project storage at
`~/Library/Application Support/WorkBench/Projects`, resolved through
Foundation's Application Support API. The former Documents-folder bookmark is
no longer required for normal operation and is read only to discover a one-time
migration source. JSON remains the internal versioned persistence format, but
direct editing is no longer a supported product interface.

When the managed library is empty and the legacy bookmark resolves, the user
may import existing Projects or start empty. Import copies only JSON files into
a temporary sibling staging directory and installs it only when copying
succeeds. It never deletes or modifies the legacy directory and refuses to
overwrite a destination that became nonempty. A new repository-initialization
preference key keeps the former repository's initialization state from
suppressing Starter Project creation in a genuinely empty managed library.

The normal first-run folder picker and bookmark-recovery UI are removed.
**Reload Projects** retains the existing unsaved-change workflow, and **Reveal
Project Library** provides explicit backup and support access without presenting
the live storage directory as a user-editable document collection.

A signed local acceptance pass imported two legacy Project files from
`~/Documents/WorkBench`. Both managed copies matched their sources byte for
byte, both sources remained in place, and the Projects appeared immediately.
After quitting and reopening the same build, WorkBench loaded the managed
library directly without presenting the import choice again.

## Generic Application Resource

The `application` Resource lets the user select any macOS `.app` bundle through
a standard open panel. It persists the bundle identifier as primary identity
and the selected absolute path as a fallback without changing schema version 2;
older WorkBench versions preserve the Resource as unsupported JSON.

`FoundationApplicationLauncher` resolves registered applications through
`NSWorkspace`, validates a fallback bundle against the stored identifier, and
opens it with normal macOS behavior. This baseline does not promise a new
window. For AeroSpace placement, the existing exact-correlation transaction
uses the stored bundle identifier and moves only one unambiguous new window.
Zero or multiple new windows are reported and existing windows remain untouched.
Safari, Chrome, Terminal, and Finder retain their enhanced compiled adapters.

`ResourceLaunchAdapterRegistry` now centralizes launch dispatch and AeroSpace
bundle identity by stable Resource type. The standard registry composes the
existing injectable launch protocols, so production and test adapters retain
their prior boundaries. Generic Application Resources remain generic even when
their bundle identifier belongs to an enhanced application such as Safari.
Missing registry entries use the existing unsupported-Resource report rather
than falling through to a parallel switch in `ProjectLauncher`.

Generic Applications can now be designated as Web Browser Resources. The
`web-browser-window` payload retains the selected bundle identifier and fallback
path and adds ordered URLs. `FoundationWebBrowserLauncher` uses `NSWorkspace`
to open those URLs with the selected application, avoiding AppleScript and
arbitrary command execution. The browser controls whether URLs form tabs in one
new window or reuse existing UI; Safari and Chrome remain the deterministic
enhanced choices. Disabling the editor option converts the Resource back to a
generic Application and intentionally removes its URL list.

A signed feature-branch acceptance build selected Brave Browser as a generic
Application, converted it with **Open as Web Browser**, saved multiple URLs, and
opened them successfully as the requested Brave tabs.

A signed real-world acceptance pass selected `/Applications/iMovie.app`, saved
its `com.apple.iMovie` bundle identity, and opened the Project with AeroSpace
workspace `8` selected. iMovie activated successfully, its newly created window
was correlated and placed in workspace `8`, and WorkBench presented no failure
report.

## Approved AeroSpace launch-destination contract

A Project may optionally name one AeroSpace workspace. WorkBench activates it
before launching Resources and places each window created for that launch in
the named workspace. Projects without a destination retain current behavior.

Activation failure stops before any Resource opens. The user may explicitly
choose **Open Without Placement** or **Cancel**. Integration enablement and
connection details are machine-specific Settings; disabling integration does
not erase Project destinations. WorkBench never edits AeroSpace configuration
and does not target named native macOS Spaces. For a Project with a destination,
its explicit placement overrides global AeroSpace routing only for windows
WorkBench creates during that launch; unrelated windows and normal application
launches remain governed by AeroSpace configuration.

## AeroSpace per-window correlation spike

A real-window spike against AeroSpace `0.21.2-Beta` validated the approved
override direction without changing production launch behavior. The typed
window query must use `list-windows --monitor all` with an explicit JSON format
requesting `window-id`, `app-bundle-id`, `app-pid`, `workspace`, and
`window-title`; plain `--json` returns only AeroSpace's default fields.

For Safari, Chrome, Terminal, and Finder, the spike recorded application window
IDs before launch, created one window, and uniquely identified the set
difference afterward. Explicit `move-node-to-workspace --window-id <id> -- 6`
moved only the new window. Existing windows retained their original workspaces.
The Chrome case began in workspace C because of an active
`on-window-detected` rule, then remained in workspace 6 after the explicit move,
confirming that WorkBench can override an immediate global routing rule without
editing AeroSpace configuration.

Production placement must never guess when the set difference contains zero or
multiple windows. It must report a placement failure, leave all candidate
windows untouched, and continue with later Resources. Window detection,
movement, and confirmation require bounded asynchronous polling and typed
errors.

## Schema v2 launch-destination foundation

Schema v2 adds an optional typed `launchDestination` object at Project level.
The initial variant is `aerospace-workspace` with a nonempty `workspace` string.
Unknown destination types are preserved as raw JSON and use placement recovery
instead of being silently ignored. Schema v1 remains readable as a Project with
no destination and is upgraded only on save; load never triggers a bulk rewrite.
Project duplication copies the destination, while the Starter Project has none.

Machine-specific `aeroSpaceIntegrationEnabled` state belongs in a typed
`UserDefaults` Settings store and defaults to false. Project JSON never contains
an executable path or socket detail. The production model, migration,
validation, Settings store, and persistence tests implement this contract.

## Typed AeroSpace client

`AeroSpaceClient` implements fixed typed operations to list all workspaces,
activate one named workspace, list windows for one application bundle
identifier, and move and confirm one explicit window ID. It discovers the CLI
at the standard Apple Silicon and Intel Homebrew locations, invokes it directly
with argument arrays, and never exposes a generic command or shell boundary.
Each command has a five-second timeout and returns a typed error for a missing
executable, process-launch failure, timeout, nonzero exit, malformed JSON, failed
focus confirmation, invalid window input, a disappeared window, or a placement
confirmation mismatch.

Activation sends the workspace name as one argument after `--`, then queries the
focused workspace and requires an exact match before reporting success. The
client remains separate from `ProjectLauncher` and is called by the application
model as an asynchronous launch preflight. A read-only check against the locally
installed AeroSpace `0.21.2-Beta` confirmed the expected JSON object shape.
Workspace control and window control use separate injectable protocols so
Settings and launch preflight do not depend on placement operations they never
invoke.

## Per-Resource AeroSpace placement coordination

`ProjectLauncher` is asynchronous and accepts an optional already-approved
placement workspace. For each supported Resource in a placed Project, it lists
that application's AeroSpace windows before invoking the adapter, polls after a
successful launch for one new window ID, moves that exact ID, relies on the
typed client to confirm its destination, and reactivates the Project workspace
before continuing. Normal-placement Projects do not query AeroSpace.

A failed initial snapshot skips that Resource because WorkBench cannot safely
correlate a subsequently created window. After a window opens, zero candidates
at the bounded deadline, multiple candidates, a query failure, or a move or
confirmation failure produces a Resource failure and never guesses a window.
WorkBench attempts to restore the Project workspace after those failures and
continues with later Resources. **Open Without Placement** remains an explicit
preflight recovery path and bypasses all per-window placement operations.

A signed local acceptance pass against AeroSpace `0.21.2-Beta` kept the
Chrome-to-workspace-`C` detection rule enabled while a Project targeted
workspace `6`. New Chrome windows finished in `6` on both the initial and
already-running-application launches, and the existing Chrome window retained
its ID and workspace. A subsequent mixed launch created one new Chrome, Safari,
Terminal, and Finder window; all four finished in `6`, while the two existing
Chrome windows remained unchanged.

After `tccutil reset AppleEvents com.example.WorkBench`, a fresh local signed
build prompted independently for Google Chrome, Safari, Terminal, and Finder.
Allowing all four produced no launch report and created one new window for each
Resource in workspace `6`; all previously observed Chrome windows retained
their IDs and placement.

A second reset exercised denial and continuation. Denying Chrome produced the
Resource error `Not authorized to send Apple events to Google Chrome.` in the
consolidated launch report. Chrome created no new window, while later Safari,
Terminal, and Finder Resources succeeded and their exact new window IDs all
finished in workspace `6`.

Re-enabling Chrome under **System Settings > Privacy & Security > Automation**
completed recovery without another prompt or launch report. The next mixed
launch again created one Chrome, Safari, Terminal, and Finder window, and every
new window finished in workspace `6`.

The signed multi-tab Chrome acceptance used Example Domain, Chromium, and Apple
in that saved order. The first launch created exactly one three-tab window in
workspace `6`. Reopening the Project preserved that window and created exactly
one additional three-tab window in `6`; both reported Apple as the active third
tab and the user visually confirmed the left-to-right tab order.

The preflight validates first, then bypasses placement for destination-free
Projects or activates and confirms a known AeroSpace destination when the
machine-local integration setting is enabled. Disabled integration, activation
failure, and unknown destination types launch no Resources and retain the
attempted Project snapshot for explicit **Open Without Placement** or **Cancel**
recovery. The Open command is disabled while activation is in progress. UI-test
doubles never contact AeroSpace or move the active workspace. After the Settings
and generic-browser increment, the complete signed scheme passes all 91 unit
tests and all 17 UI tests.

## AeroSpace Settings and Project editor

The native Settings scene owns an observable machine-local Settings model. Its
enable toggle writes through to `UserDefaults` immediately; while enabled, the
user may check the AeroSpace connection and see the reported workspace names or
a typed discovery error. UI tests use an isolated in-memory store, so they never
alter the developer's real integration preference.

**Project Settings** is an explicit row action that clears Resource selection.
Using an optional `nil` List-selection tag made the row appear selectable but
did not reliably return from Resource properties to Project properties. UI
coverage now selects a Resource first and verifies that Project Settings exposes
the launch-destination controls.

The Resources column now begins with a selectable **Project Settings** row, and
selecting a Project lands on that row rather than implicitly selecting its first
Resource. Project Settings offers normal placement or AeroSpace placement. An
AeroSpace destination has an editable workspace field for offline and portable
configuration, an explicit refresh action, and a menu of reported workspaces.
Discovery never replaces a manual value unless the user chooses a reported
workspace. Unsupported destinations remain visible and preserved.

## AeroSpace sandbox communication spike

The spike used AeroSpace `0.21.2-Beta` and compared its Homebrew CLI with the
documented Unix-domain socket from signed ad-hoc app bundles. All workspace
checks were non-destructive: list all workspaces, list the focused workspace,
attempt to select that same workspace with `--fail-if-noop`, and submit an
invalid command to inspect failure reporting.

The CLI works from an unsandboxed process and returns structured JSON for
workspace discovery. From a signed App Sandbox bundle, however,
`/opt/homebrew/bin/aerospace` is not visible or executable. Adding the outbound
network-client entitlement does not change executable access.

A direct socket client implemented AeroSpace protocol version 1, including the
version handshake and length-prefixed JSON request and response frames. The
App Sandbox denied `connect` to
`/tmp/bobko.aerospace-<user>.sock` with `EPERM`. The result was identical with
and without the outbound network-client entitlement. No workspace was changed.

Therefore neither an assumed CLI path nor direct socket access is viable under
WorkBench's current sandbox entitlements.

A follow-up signed proof selected the AeroSpace CLI through `NSOpenPanel`,
created an app-scoped security-scoped bookmark, balanced scoped access, and
attempted the same fixed operations through `Process`. The second app launch
restored the bookmark without displaying the picker, proving persistence, but
both the initial and restored launches failed before process creation with
`NSCocoaErrorDomain` code 256 (`Could not open() the item`). Selecting and
bookmarking an external executable therefore does not make it executable from
the sandbox.

All narrow sandbox-compatible candidates tested were blocked. The approved
resolution is to disable App Sandbox for both Debug and Release while retaining
Hardened Runtime and its Apple Events Automation entitlement. Sandbox-only file
access and temporary Apple Event exception entitlements were removed. The app
is therefore not eligible for Mac App Store distribution without revisiting
this architecture.

Disabling the sandbox changes the app's preferences location, so the first
unsandboxed launch asks the user to select the existing WorkBench configuration
folder again. Project JSON files are not moved or rewritten. Directory
persistence now uses a normal Foundation bookmark; scoped bookmark creation
fails outside the sandbox, and direct filesystem access needs no scoped-access
lifetime.

The standalone signed Debug build succeeds. Its embedded entitlements contain
Apple Events Automation and the Debug `get-task-allow` entitlement, with no App
Sandbox entitlement. All 48 unit tests and all 13 signed UI tests pass. The UI
tests invoke Save through its existing File command and now invoke Open Project
through a File command with the standard Command-O shortcut, so verification is
independent of whether macOS places trailing toolbar items in its overflow
menu. The build continues to emit the expected warning that App Intents
metadata extraction is skipped because the app does not link App Intents.

## Baseline

- Xcode: 26.6 (build 17F113)
- macOS SDK: 26.5
- Swift: 6.3.3
- Deployment target: macOS 26.0
- UI framework: SwiftUI
- Swift language mode: Swift 6
- Strict concurrency checking: complete
- Default actor isolation: Main Actor for the application target
- App Sandbox: disabled
- Hardened Runtime: enabled
- Dependencies: none
- Provisional bundle identifier: `com.example.WorkBench`

The bundle identifier must be replaced with an appropriate reverse-DNS identifier before signing or distribution.

## Targets

- `WorkBench`: native macOS application
- `WorkBenchTests`: hosted unit-test bundle

Generated Info.plist files are used for both targets. The checked-in entitlements retain only Hardened Runtime Apple Events Automation. App Sandbox and its user-selected file, app-scoped bookmark, and temporary Apple Event exception entitlements were removed for AeroSpace compatibility. Safari, Terminal, and Finder were established by the Phase 1 spikes; Chrome was added as a later Resource type and still requires signed integration verification.

The app includes a custom macOS icon depicting three organized workspace panels
on a workbench with a subtle launch motif. A standard `AppIcon.appiconset`
provides all macOS renditions from 16×16 through 1024×1024; Release builds compile
them into `AppIcon.icns` and `Assets.car` with `CFBundleIconName` set to `AppIcon`.

## Verification

The complete application and test suite pass with normal ad-hoc signing:

```bash
xcodebuild test \
  -project WorkBench.xcodeproj \
  -scheme WorkBench \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WorkBenchSignedDerivedData
```

An unsigned run must be limited explicitly to `WorkBenchTests` with
`-only-testing:WorkBenchTests`. An unsigned command must never include
`WorkBenchUITests`, because macOS rejects the unsigned UI-test runner as
damaged.

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

Hardening verification used an isolated ad-hoc signed build with bundle identifier
`com.example.WorkBench.DirectoryAccessTest` and a temporary `/tmp` configuration
folder, leaving the real configuration and bookmark untouched. With no stored
bookmark, WorkBench presented folder selection and accepted the temporary folder;
a separate launch restored it without prompting. Removing directory permissions
returned WorkBench to folder selection with the write-probe failure, and replacing
the bookmarked folder caused macOS to mark the bookmark stale and WorkBench to show
"Access to the WorkBench folder has expired. Select it again." The temporary folder
and DerivedData were removed after verification.

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

The Project repository is implemented behind injected directory, initialization-state, and atomic-writer interfaces. Production operations use the selected configuration directory directly, while tests use isolated temporary directories.

Repository behavior includes:

- deterministic discovery of JSON files and sorting of valid Projects by friendly name;
- file-specific visible issues for malformed JSON, invalid Projects, duplicate names, and filenames that do not match the Project's stable UUID filename;
- atomic Project saves with validation and case-insensitive unique-name enforcement;
- Starter Project creation only on the first successful load of a genuinely uninitialized empty repository;
- a durable initialization marker written only after the Starter Project file is saved successfully;
- deletion of only the requested stable-identifier file, with confirmation remaining the responsibility of the later workflow layer; and
- semantic preservation of unsupported Resource JSON across repository load and save.

Repository calls are currently synchronous and main-actor isolated, matching the small local JSON files expected for the MVP. Responsiveness must be reviewed when the repository is connected to the interface; file work should move off the main actor if measurements show noticeable blocking.

Manual hardening used an isolated signed build and temporary configuration to
verify external JSON editing through the visible interface. A valid hand edit
renamed Starter Project and added an unsupported Future Resource; a separate
malformed `broken.json` remained visible as a configuration issue. WorkBench
displayed the future type and preservation guidance. After renaming the Project
in the GUI, saving, and reloading, exact JSON inspection confirmed that the
unsupported Resource retained its UUID, name, type, boolean field, nested number,
and nested string array. The isolated configuration and DerivedData were removed.

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

`WorkBenchApplicationModel` owns presentation coordination without moving filesystem calls into views. It connects managed-library preparation and migration, repository startup, draft commands, error presentation, deletion confirmation, and unsaved-change choices. Window close and standard application termination use the same workflow decisions as Project selection and Reload Projects.

The application uses a SwiftUI `Window` scene rather than a multi-window group. Save and Reload Projects are standard menu commands; Reload uses Command-Shift-R. Reveal Project Library provides explicit support and backup access. No status-bar item is created. Project launching is intentionally absent from this phase and will connect to the proven Automation adapters through the Phase 6 launch coordinator.

Manual hardening verified keyboard traversal, arrow-key list navigation, form
focus, dirty-state behavior, and VoiceOver labels. The 840×520 minimum and a
large window layout remain practical. The initial automatic toolbar style kept
all actions icon-only even with ample width, making Open Project difficult to
discover. New, Open Project, Save, Duplicate, and Delete now explicitly use
title-and-icon labels in one prioritized window-level primary toolbar group.
This placement keeps the Project title beside the sidebar in the production
`Window` scene and preserves New, Open, and Save ahead of Duplicate and Delete
when macOS moves trailing actions into native overflow at narrower widths.
The same five Project actions appear in the File menu in that order, so every
toolbar action remains available when its button is overflowed. New Project
uses Command-N; Open and Save retain Command-O and Command-S.

Safari, Chrome, and generic Web Browser URL rows expose the same move-up and
move-down controls. Reordering changes the persisted URL array, which is the tab
creation order used by each browser launcher.

The AppKit save-before-closing alert explicitly loads the running bundle's icon
through `NSWorkspace`. This keeps lifecycle prompts branded with the WorkBench
icon in both the production Window scene and the custom automated-test host.

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

The Terminal adapter initially activated Terminal before sending its `do script` command. During manual verification, a newly created Terminal session appeared to receive the home-directory `cd` twice. The adapter now creates the scripted session before activating Terminal, and automated coverage verifies that ordering. A signed-build retest initially showed a single `cd`, but a later repeated Project launch displayed it twice again. The final directory remained correct, so this was a cosmetic limitation rather than a launch failure and motivated the home-directory special case below.

The home-directory special case has sufficiently resolved the duplicate-`cd`
behavior for the MVP; any intermittent cosmetic display is accepted and does
not require further work in the current scope.

Home-relative Terminal sessions stored as `~` or `~/` now create a normal empty
Terminal session without injecting `cd`. This avoids Terminal's intermittent
duplicate display for the common home-directory case. Terminal's profile and
shell startup behavior determine that session's initial directory. All other
configured paths retain the explicit `cd` so WorkBench continues to enforce the
requested working directory.

Repeated Project opening was manually verified by comparing application window counts before and after another launch. Safari, Terminal, and Finder each gained exactly one window, confirming that WorkBench does not reuse the previously opened workspace windows. Permission-denial recovery has not yet been manually verified.

## Chrome Window Resource

The generic Browser Window presentation now reads Safari Window while retaining
the existing `browser-window` JSON type for backward compatibility. Chrome is a
separate `chrome-window` Resource using the same ordered-tab payload. Older
WorkBench versions therefore preserve Chrome Resources as unsupported JSON
without confusing existing Safari configurations or requiring a schema-version
migration.

`ChromeLauncher` uses a separately injected `BrowserLaunching` adapter and
creates a new Google Chrome window, assigns its first tab, appends remaining
tabs in order, and selects the final tab. The sandbox exception is narrowly
extended to `com.google.Chrome`. Automated tests cover JSON round trips,
Chrome-specific validation, default naming, launch ordering and continuation,
and escaped AppleScript construction. A signed sandboxed launch against the
real Google Chrome application and permission-denial recovery remain manual
verification items.

When Automation starts Chrome from a fully quit state, Chrome creates its own
initial window before handling WorkBench's script. Creating another window
unconditionally therefore produced two windows. The launcher now records
whether Chrome was already running: a cold launch reuses Chrome's initial
window after a bounded five-second wait, while an already-running Chrome still
receives a new window so repeated Project opens remain independent.

## Resource removal crash fix

Manual hardening found a crash when a newly added Safari Window was selected and immediately removed. The outgoing SwiftUI property editor reevaluated a binding that captured the Resource's former array index after the Resource had been deleted, causing an out-of-bounds subscript trap.

Resource property bindings and tab actions now use the stable `ResourceID` to find the current array position at access time. Missing Resources and stale tab positions safely return or no-op, and selection is cleared before removal mutates the draft. The full automated suite passes, and the original add-select-remove sequence was repeated successfully in a signed build without a crash.

## UI test implementation

The first macOS UI-test slice is implemented and verified:

- a `WorkBenchUITests` macOS UI-test target in the existing `WorkBench` scheme;
- stable accessibility identifiers for the Project and Resource lists, Project
  name field, unsaved-changes indicator, Open Project button, and Save button;
- Debug-only UI-test startup selected by explicit launch argument, launch
  environment, and AppKit launch-default signals;
- an in-memory Project repository seeded with Starter Project; and
- no-op Safari, Terminal, and Finder launch adapters so UI tests cannot open
  external applications.

The UI-test model starts with synthetic ready directory access and is displayed
in a retained AppKit-hosted window. This avoids SwiftUI's restorable single
window reopening with no visible window under command-line XCTest. Both paths
are compiled only in Debug builds and still require the explicit UI-test signal.

`testStarterProjectCanBeRenamedAndSaved()` verifies that Starter Project is
visible, editing its name enters dirty state, Save is enabled, saving clears the
unsaved indicator, and the renamed Project appears in the list.

The first test command incorrectly retained the old unit-test setting
`CODE_SIGNING_ALLOWED=NO`. macOS reported the temporary app as damaged because a
UI test must launch its app and runner. No repository or installed application
was damaged. Do not use `CODE_SIGNING_ALLOWED=NO` for runs that include
`WorkBenchUITests`.

A fresh, normally ad-hoc-signed build under
`/tmp/WorkBenchSignedDerivedData` launches without the damaged-app alert. The
isolated UI target passes with:

```bash
xcodebuild test \
  -project WorkBench.xcodeproj \
  -scheme WorkBench \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WorkBenchSignedDerivedData \
  -only-testing:WorkBenchUITests
```

The 48-test `WorkBenchTests` target also passes independently. Its login-home
test now derives the expected home from the POSIX password database because
Foundation's named-user lookup returns the app-container home under the current
macOS test sandbox. The complete signed scheme passes all 48 unit tests and all
twelve UI tests together. Xcode intermittently reports that it cannot collect an OS log
archive because `version.plist` cannot be read; this post-test infrastructure
warning does not affect test execution or results. Terminal's App Management
permission may be revoked after command-line UI testing is complete.

The UI-test fixture now includes a deterministic empty Second Project. A second
end-to-end test edits a Project and attempts to switch selection three times,
verifying Cancel, Discard Changes, and Save. Cancel leaves the edit pending so
the next switch prompts again, Discard restores the repository value before
switching, and Save persists the renamed Project before completing the switch.

A third end-to-end test selects the Starter Project's Home Terminal Resource,
edits its name and working directory through the visible property fields, saves,
and verifies that the saved values remain visible. Stable accessibility
identifiers on those fields keep the test independent of localized field labels.

A fourth end-to-end test uses XCTest's macOS click-and-drag gesture to move Home
Folder ahead of Web. It verifies the changed visible order, saves the Project,
and confirms that the order remains changed after the save completes.

A fifth end-to-end test selects Second Project and exercises both outcomes of
the deletion confirmation. Cancel keeps the Project visible; reopening the
confirmation and choosing Delete removes only Second Project while Starter
Project remains available.

A sixth end-to-end test creates Untitled Project and duplicates it as Untitled
Project Copy. Each remains absent from the Projects sidebar while it is an
unsaved draft, then appears after Save, confirming the visible draft-first
creation and duplication workflow and deterministic unique naming.

A seventh end-to-end test changes Home Terminal to an invalid relative path and
invokes Open Project. It verifies the consolidated launch-report title and path
validation guidance, then dismisses the report. Validation stops launch before
the Debug-only no-op adapters can be called, so no external application opens.

An eighth end-to-end test verifies that a malformed Project file remains visible
as a configuration issue and that an unsupported Resource remains selectable,
identifies its preserved type, and does not prevent its Project from being opened.

A ninth end-to-end test invokes Reload Projects through its Command-Shift-R
shortcut with dirty edits. It verifies that Cancel preserves the draft, Discard
restores the repository value, and Save persists the edit before reload continues.

A tenth end-to-end test closes the window with dirty edits and exercises the
native lifecycle alert. It verifies that Cancel keeps the window open while
Discard Changes and Save complete the requested close.

An eleventh end-to-end test invokes Quit WorkBench with dirty edits. It verifies
that Cancel keeps the process running while Discard Changes and Save allow
application termination to complete.

A twelfth end-to-end test launches with deterministic expired configuration-folder
access. It verifies the recovery heading and guidance, enabled folder chooser,
and absence of the Projects editor until access is restored.
