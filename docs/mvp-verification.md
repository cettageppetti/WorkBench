# WorkBench MVP Verification Status

This document tracks verification of the testable requirements in
`product-requirements.md`. It distinguishes automated coverage from manual
evidence so that a successful unit-test run is not mistaken for completion of
the MVP acceptance scenario.

Status was reviewed on July 18, 2026 against the schema v2 implementation
working tree following commit `45bd6ec`.

## Automated verification

The hosted `WorkBenchTests` target covers:

- schema versions 1 and 2, migration only on explicit save, supported and
  unsupported Resource and launch-destination round trips, stable identifiers
  and filenames, validation, path syntax and login-home expansion;
- Starter Project contents and Resource order;
- repository initialization, deterministic loading, visible invalid files,
  duplicate detection, atomic-save failure behavior, deletion, reload, and
  unsupported Resource preservation;
- draft dirty state, explicit save, Save/Discard/Cancel behavior, creation,
  duplication, deletion failure, Resource mutation, and persisted ordering;
- folder selection, bookmark restoration, and missing or stale bookmark
  recovery decisions;
- machine-local AeroSpace integration enablement, including its disabled
  default and persistence independently of Project JSON;
- typed AeroSpace workspace discovery and activation arguments, command
  failures, timeouts, JSON parsing, and post-activation focus confirmation;
- launch validation, sequential ordering, continuation after failure, missing
  paths, unsupported Resources, and parameterized AppleScript construction; and
- application-model coordination for creation, Resource commands, unsaved
  selection changes, and consolidated invalid-launch reports.

The signed `xcodebuild test` command passes all 63 unit tests and all thirteen
macOS UI tests. The build emits the expected metadata-extraction warning because
WorkBench does not link App Intents. Xcode may also report debugger-version
store noise or fail to collect a post-test OS log archive because
`version.plist` is unreadable; test execution still succeeds.

The `WorkBenchUITests` target uses an explicitly selected Debug-only in-memory
repository, synthetic ready directory access, no-op external-application
adapters, and a retained test window. Its end-to-end tests cover selecting
Starter Project, renaming it, observing dirty state, explicitly saving, and
observing the saved name and cleared dirty state. A two-Project fixture also
verifies that switching Projects with unsaved edits supports Cancel, Discard
Changes, and Save, including preserving edits after Cancel, restoring the saved
value after Discard, and persisting a rename before completing the switch. A
Resource editing test selects Home Terminal, changes its name and working
directory, saves, and verifies the persisted values in the visible interface.
A drag-reordering test moves Home Folder ahead of Web, saves, and verifies that
the visible order remains changed. A Project deletion test verifies that Cancel
preserves Second Project and Delete removes it while retaining Starter Project.
A creation and duplication test verifies draft-only names before Save and the
persisted unique names afterward. A launch-report test makes Home Terminal's
path invalid, invokes Open Project, verifies the consolidated validation report,
and dismisses it without invoking any external-application adapter. An issue and
unsupported-Resource test verifies that malformed files remain visible and that
future Resource types remain selectable with their preservation guidance.
A Reload command test verifies that unsaved edits can be cancelled, discarded,
or saved before repository reload continues.
A window-close test verifies that the native unsaved-changes alert can cancel
the close or complete it after discarding or saving the draft.
A quit-command test verifies that the same choices either cancel termination or
allow the application process to exit after discarding or saving the draft.
A configuration-directory recovery test verifies the first-launch presentation,
recovery guidance, enabled chooser action, and hidden Projects editor.

## Manually verified

- The earlier signed sandboxed build restored access to a selected
  `~/Documents/WorkBench` directory through an app-scoped bookmark.
- The earlier isolated signed sandboxed build presented folder selection when its bookmark
  is missing, restores a selected temporary folder after relaunch, returns to
  folder selection with write-failure guidance when access is denied, and shows
  expired-access guidance when macOS marks the bookmark stale.
- An isolated signed build loads a valid hand edit, keeps malformed JSON visible
  as a file-specific issue, identifies an unsupported Resource, and preserves
  that Resource's extra boolean and nested JSON fields across GUI save/reload.
- Keyboard traversal, list navigation, form focus, dirty-state behavior, and
  VoiceOver labels were reviewed manually. Minimum and large layouts remain
  usable; toolbar actions show title-and-icon labels when space permits and move
  into native overflow without overlap at the minimum size.
- Starter Project opens new Safari, Terminal, and Finder windows in order.
- Reopening Starter Project creates one additional window in each application.
- Adding, selecting, and immediately removing a Safari Window no longer
  crashes after the stable-identifier binding fix.

These results are recorded in `../IMPLEMENTATION_NOTES.md` and should be
repeated during final acceptance verification.

## Verification still required

The signed unsandboxed suite passes all 63 unit tests and all 13 UI tests. Save
and Open verification uses stable File commands rather than assuming macOS has
kept trailing toolbar controls outside its overflow menu. The standalone signed
app build succeeds and contains no App Sandbox entitlement.

### Automated UI coverage

The planned automated UI interaction coverage is complete.

Adding controlled launch behavior for UI tests must not become a production
back door or weaken the Automation boundary.

### Manual acceptance and permissions

- Exercise Automation permission denial and revocation independently for
  Safari, Chrome, Terminal, and Finder; verify later Resources are still attempted and
  recovery guidance names the affected application.
- Verify a signed Chrome Window launch creates a new window with tabs
  in saved order and that repeated launch creates another window.
- Run the complete acceptance scenario from a clean configuration and clean
  privacy-permission state.
- Measure UI responsiveness during repository operations and a complete
  Resource launch.

### Release preparation

- Replace the provisional `com.example.WorkBench` bundle identifier before
  signing for distribution.
- Reassess the targeted temporary Apple Events exceptions for the intended
  distribution channel.
- Review the intermittent cosmetic duplicate `cd` display in Terminal and
  either resolve it or retain it as a documented limitation.
- Perform a clean build, review warnings, rerun all automated tests, and inspect
  the final diff for generated artifacts, secrets, and unrelated changes.

## Completion rule

The MVP should be marked complete only after every item above is either verified
or deliberately accepted as a documented limitation. Automated tests of model
coordination do not replace UI interaction or clean-state permission testing.
