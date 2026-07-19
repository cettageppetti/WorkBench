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
  unsupported Resource and launch-destination round trips, generic Application
  Resource identity and validation, stable identifiers
  and filenames, validation, path syntax and login-home expansion;
- Starter Project contents and Resource order;
- repository initialization, deterministic loading, visible invalid files,
  duplicate detection, atomic-save failure behavior, deletion, reload, and
  unsupported Resource preservation;
- draft dirty state, explicit save, Save/Discard/Cancel behavior, creation,
  duplication, deletion failure, Resource mutation, and persisted ordering;
- Application Support path creation, legacy bookmark discovery, staged
  copy-based migration, source preservation, clean-start behavior, and
  destination overwrite prevention;
- machine-local AeroSpace integration enablement, including its disabled
  default and persistence independently of Project JSON;
- typed AeroSpace workspace discovery and activation arguments, command
  failures, timeouts, JSON parsing, and post-activation focus confirmation;
- typed AeroSpace application-window queries, exact window-ID movement,
  destination confirmation, and invalid or disappeared-window failures;
- generic application selection, default launch dispatch, missing-application
  failure, and bundle-identifier-based AeroSpace placement;
- compiled launch-registry coverage, including all supported bundle identities,
  registry-owned dispatch, and generic-versus-enhanced behavior separation;
- launch-preflight ordering, destination-free bypass, disabled and failed
  placement recovery, unknown destinations, and captured fallback launches;
- per-Resource window snapshots, unique correlation, bounded detection,
  ambiguous-candidate safety, movement failure reporting, workspace restoration,
  and continuation with later Resources;
- Settings enablement and discovery presentation plus Project destination
  editing, manual workspace persistence, and deterministic UI isolation;
- launch validation, sequential ordering, continuation after failure, missing
  paths, unsupported Resources, and parameterized AppleScript construction; and
- application-model coordination for creation, Resource commands, unsaved
  selection changes, and consolidated invalid-launch reports.

The signed `xcodebuild test` command passes all 89 unit tests and all sixteen
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
A legacy-migration presentation test verifies the import and start-empty choices
and keeps the Projects editor hidden until the user resolves migration.

## Manually verified

- Earlier bookmark and selected-folder results apply only to migration
  compatibility. Production now uses an application-managed Project library in
  the user-domain Application Support directory.
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

The AeroSpace placement acceptance pass retained a conflicting global Chrome
rule targeting workspace `C` while WorkBench targeted workspace `6`. Initial
and repeated Chrome launches finished in `6`; the repeated launch preserved the
existing Chrome window. A mixed Chrome, Safari, Terminal, and Finder launch
placed exactly one new window from each Resource in `6` and did not move the two
existing Chrome windows.

A clean Automation-permission pass reset Apple Events approval for
`com.example.WorkBench`. The next mixed launch prompted independently for
Chrome, Safari, Terminal, and Finder. Allowing every prompt produced no launch
report, placed one new window per Resource in workspace `6`, and preserved the
existing Chrome windows.

In a controlled denial pass, denying Chrome produced the expected Apple Events
authorization failure in the consolidated launch report and no new Chrome
window. Safari, Terminal, and Finder still launched afterward, and each new
window was confirmed in workspace `6`.

Re-enabling Chrome in System Settings completed permission recovery. The next
mixed launch required no new prompt, produced no failure report, and placed all
four newly created application windows in workspace `6`.

A signed Chrome acceptance launch opened Example Domain, Chromium, and Apple in
saved left-to-right order in one new window in workspace `6`. Reopening the
Project preserved the first window and created exactly one additional ordered
three-tab window in `6`.

## Verification still required

The signed unsandboxed suite passes all 89 unit tests and all 16 UI tests. Save
and Open verification uses stable File commands rather than assuming macOS has
kept trailing toolbar controls outside its overflow menu. The standalone signed
app build succeeds and contains no App Sandbox entitlement.

### Automated UI coverage

The planned automated UI interaction coverage is complete.

Adding controlled launch behavior for UI tests must not become a production
back door or weaken the Automation boundary.

### Manual acceptance and permissions

Managed Project storage migration has passed signed local acceptance. Two
legacy JSON files were copied from `~/Documents/WorkBench` to the Application
Support Project library, verified byte-for-byte, and left intact at the source.
The Projects loaded after import and again after a full quit and relaunch, with
no repeated migration prompt.

Generic Application Resource integration has passed signed local acceptance
with iMovie. WorkBench selected `/Applications/iMovie.app`, persisted its
`com.apple.iMovie` bundle identity, activated it through its default macOS
behavior, correlated its new window, and placed that window in the Project's
selected AeroSpace workspace `8` without a failure report.

- Exercise Automation permission denial and revocation independently for
  Safari, Terminal, and Finder. Chrome denial, later-Resource continuation,
  application-specific reporting, and System Settings recovery are verified.
- Run the complete acceptance scenario from a clean configuration and clean
  privacy-permission state.
- Measure UI responsiveness during repository operations and a complete
  Resource launch.

### Release preparation

- Replace the provisional `com.example.WorkBench` bundle identifier before
  signing for distribution.
- Reassess the targeted temporary Apple Events exceptions for the intended
  distribution channel.
- The intermittent cosmetic duplicate `cd` display in Terminal is sufficiently
  resolved by the home-directory special case and is accepted for the MVP.
- Perform a clean build, review warnings, rerun all automated tests, and inspect
  the final diff for generated artifacts, secrets, and unrelated changes.

## Completion rule

The MVP should be marked complete only after every item above is either verified
or deliberately accepted as a documented limitation. Automated tests of model
coordination do not replace UI interaction or clean-state permission testing.
