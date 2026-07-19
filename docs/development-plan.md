# WorkBench MVP Development Plan

## Delivery approach

Build WorkBench as a sequence of small, testable vertical increments. Each phase should leave the repository buildable, keep unrelated changes out of the diff, and end with reviewed warnings and passing relevant tests.

Do not begin a later phase when an earlier architecture or permission risk remains unresolved unless the work is independent. Changes to dependencies, persistence schema, sandbox strategy, security/privacy behavior, or public interfaces require explicit approval.

## Phase 0: Development baseline

### Outcomes

- Confirm full Xcode remains selected as the active developer directory. Verified initial path: `/Applications/Xcode.app/Contents/Developer`.
- Use the verified initial toolchain baseline: Xcode 26.6, Swift 6.3.3, and macOS SDK 26.5.
- Choose the exact initial deployment target based on the installed SDK; no backward-compatibility commitment is required for the MVP.
- Create the macOS app and test targets with SwiftUI, Swift strict concurrency, App Sandbox, and no third-party dependencies.
- Establish build and test commands suitable for local development.
- Add `IMPLEMENTATION_NOTES.md` as the evolving record requested by `DIRECTION.md` once implementation begins.

### Verification

- A clean debug build succeeds.
- The empty test targets run successfully.
- Build warnings are reviewed and recorded or resolved.
- Generated build artifacts remain untracked.

## Phase 1: Risk-reduction spikes

Resolve platform risks before investing in the full interface. Spike code should either become tested production adapters or be removed; do not leave a parallel prototype architecture.

### Filesystem access spike

- Verify a sandboxed app can create, read, atomically replace, and delete files under `~/Documents/WorkBench` with the intended entitlement strategy.
- Verify first-access behavior on a clean machine or clean permission state.
- Document any App Store or signing limitations discovered.

The spike confirmed that fixed Documents access is unavailable under App Sandbox. The original selected-directory flow was later superseded by an application-managed Project library under Application Support; its bookmark remains only for one-time migration discovery.

### Application Automation spike

- Open a new Safari window with `https://apple.com` and `https://ibm.com` in order.
- Open a new Terminal window at the user's home directory.
- Open a Finder window at the user's home directory.
- Exercise allowed, denied, and revoked Automation permissions.
- Determine the narrowest reliable system API for each integration.

The allowed-permission path is verified in a signed sandboxed build for Safari, Terminal, and Finder. Denied and revoked permission recovery remains to be checked during MVP hardening.

### AeroSpace communication spike

- Compare typed workspace discovery and activation through the AeroSpace CLI
  and documented Unix-domain socket from a signed sandboxed app.
- Confirm the minimum required entitlements and record failure behavior without
  moving to a different workspace.
- Keep connection details machine-specific and do not introduce a generic
  command runner.

The original App Sandbox could not see the assumed Homebrew CLI path and denied the
documented socket connection with `EPERM`; outbound network-client access does
not alter either result. A second signed proof confirmed that a user-selected
CLI bookmark persists across launches, but scoped access still cannot execute
the external binary (`NSCocoaErrorDomain` code 256). The approved resolution is
to disable App Sandbox, retain Hardened Runtime, and use only fixed typed
AeroSpace operations.

### Verification

- Manual results and permission requirements are documented.
- Failures are represented as values suitable for a consolidated launch report.
- No Resource failure terminates the process or blocks an independent adapter test.

## Phase 2: Domain model and JSON schema

### Outcomes

- Implement strongly typed Project and Resource identifiers.
- Implement Project, supported Resource payloads, unsupported Resource preservation, and ordered Resource collections.
- Define schema version 1 and stable UUID-based filenames.
- Implement path syntax validation and home-directory expansion.
- Implement Project and Resource validation independently of SwiftUI and external applications.
- Create the canonical Starter Project factory.

### AeroSpace schema v2 increment

- Add an optional typed Project `launchDestination` with the
  `aerospace-workspace` variant and lossless unknown-destination preservation.
- Decode schema v1 as a destination-free Project and encode schema v2 only when
  a Project is saved; do not bulk-rewrite files during load.
- Copy launch destinations when duplicating Projects and keep the Starter
  Project destination-free.
- Persist machine-specific integration enablement separately in `UserDefaults`,
  defaulting to disabled; never store executable paths or socket details in
  Project JSON.
- Cover v1 migration, v2 round trips, unknown destination preservation,
  validation, duplication, and disabled-setting behavior with unit tests before
  adding UI or external AeroSpace calls.

### Typed AeroSpace client increment

- Add injectable typed operations for workspace discovery and activation.
- Invoke the CLI directly with argument arrays from standard Homebrew locations;
  do not introduce a shell or generic command runner.
- Bound every command and preserve distinct unavailable, launch, timeout,
  command, response, and focus-confirmation failures.
- Confirm the requested workspace is focused before activation succeeds.
- Keep launch-preflight recovery and Settings/editor UI in later increments.

### AeroSpace launch-preflight increment

- Validate before invoking AeroSpace or any Resource adapter.
- Activate and confirm a configured workspace before launching Resources.
- Treat disabled integration, activation errors, and unknown destinations as
  recoverable placement failures that initially launch nothing.
- Capture the attempted Project for explicit **Open Without Placement** or
  **Cancel** recovery and prevent concurrent Open requests.
- Exercise recovery through deterministic UI-test adapters that never contact
  the user's AeroSpace process.

### AeroSpace Settings and editor increment

- Add a native Settings scene for machine-local enablement and connection
  checks, with actionable discovery failures.
- Make Project-level properties explicitly selectable above the Resource list.
- Offer normal placement, manual AeroSpace workspace entry, refresh, and
  user-selected reported workspace names without overwriting portable values.
- Keep Settings UI tests isolated from real preferences and AeroSpace state.

### Automated tests

- Supported Resource encode/decode round trips
- Unknown Resource lossless round trips
- Newer or malformed schema handling
- Missing and duplicate identifiers
- Empty and duplicate Project names
- URL parsing without an HTTP/HTTPS-only restriction
- Absolute and `~` path acceptance and other relative-path rejection
- Correct Starter Project name, Resource order, URLs, and paths

### Exit criteria

- The version 1 schema is documented alongside representative JSON.
- Domain tests pass without filesystem or application Automation access.
- Adding another Resource type would not require changing Project identity or ordering behavior.

## Phase 3: Project repository

Implementation status: repository behavior and isolated integration tests are complete. User-facing reload and delete confirmation remain workflow/interface responsibilities in Phases 4 and 5.

### Outcomes

- Create and discover the Projects directory.
- Load valid Projects and report malformed or invalid files as visible results.
- Detect duplicate Project names and identifiers.
- Save Project files atomically using stable identifier filenames.
- Delete a Project file only after confirmation is supplied by the workflow layer.
- Bootstrap Starter Project only for a genuinely uninitialized repository.
- Preserve a durable initialized state so intentional deletion does not recreate Starter Project.
- Reload the managed Project library on demand.

### Automated tests

- Empty first run creates exactly one Starter Project.
- Later empty repositories do not recreate an intentionally deleted Starter Project.
- Valid files load deterministically.
- Invalid JSON and invalid Projects remain represented with file-specific errors.
- Unknown Resource payloads survive load and save.
- Save failure retains the previous valid file.
- Rename does not change the filename.
- Duplicate creates new Project and Resource identifiers and a unique name.
- Delete success and delete failure produce correct repository state.
- Reload reflects the latest managed repository state.

### Exit criteria

- All repository tests use isolated temporary directories.
- Tests never read or write the developer's real Application Support Project library.
- Partial writes and silent file omission are covered by tests.

## Phase 4: Draft editing workflows

Implementation status: the UI-independent workflow state machine and automated tests are complete. Presenting dialogs and connecting standard window and application commands remain Phase 5 interface work.

### Outcomes

- Maintain separate persisted and draft Project values.
- Track dirty state reliably.
- Implement create, select, rename, duplicate, delete, save, and reload workflows.
- Implement add, edit, remove, and reorder Resource workflows.
- Centralize Save/Discard/Cancel handling for Project switching, window close, quit, and reload.
- Ensure a failed Save cancels the pending action and retains the draft.

### Automated tests

- Every edit type enters dirty state.
- Successful save clears dirty state.
- Discard restores the persisted snapshot.
- Cancel preserves selection and draft.
- Switching, closing, quitting, and reloading share the same prompt semantics.
- Save failure prevents navigation or termination continuation.
- Unique Project names are enforced for create, rename, duplicate, load, and save.
- Reordering is persisted and becomes launch order.

## Phase 5: Core SwiftUI interface

Implementation status: the production single-window editor, standard Save/Reload commands, validation display, deletion confirmation, unsupported-Resource display, and lifecycle prompt wiring are implemented. Automated UI interaction tests and final manual accessibility/layout review remain hardening work; real Project opening belongs to Phase 6.

### Outcomes

- Build the single-window three-column interface using native SwiftUI controls.
- Present Projects, Resources, properties, dirty state, and contextual validation.
- Add Resource creation and drag-to-reorder behavior.
- Add Project commands and deletion confirmation.
- Wire **Reload Projects**, **Reveal Project Library**, and normal macOS termination behavior into standard application menus.
- Present invalid files and unsupported Resources without making them disappear.
- Keep views free of direct filesystem and Apple Event operations.

### Automated tests

- UI tests cover first launch, selection, editing, explicit save, discard, cancel, deletion confirmation, and drag reordering.
- Invalid JSON is visible and non-launchable.
- Unsupported Resources are visible and distinguishable from invalid Resources.
- Menu reload uses unsaved-change handling.

### Manual review

- Keyboard navigation, focus, labels, and common accessibility behavior are usable.
- Layout behaves at practical minimum and larger window sizes.
- Controls and menu placement follow normal macOS conventions.
- No menu-bar status item is present.

## Phase 6: Resource launch coordination

Implementation status: the production coordinator, parameterized adapters,
generic Application Resource, structured report, UI command, and automated
tests are complete. A signed build has successfully opened the real Starter
Project in Safari, Terminal, and Finder, including creating another window in
each application when opened repeatedly. Generic Application Resource signed
integration and denied-permission recovery remain manual verification items.

### Outcomes

- Implement the sequential Project launcher and structured LaunchReport.
- Connect supported Resources to the isolated Safari, Terminal, and Finder adapters proven in Phase 1.
- Open a user-selected macOS application through its bundle identity and saved
  fallback path without scripts or a generic command runner.
- Skip unsupported Resources while continuing known Resources.
- Continue after path, permission, application, or scripting failures.
- Present one consolidated result after all launch attempts when any item failed or was skipped.
- Allow repeated Project opens to create new instances without window reuse.

### Automated tests

- Resources are attempted exactly in saved order.
- The next attempt begins after the prior adapter returns.
- A failure does not suppress later attempts.
- Unsupported Resources are skipped and reported.
- Invalid Projects do not begin launching.
- Success, partial failure, total failure, and permission denial produce correct reports.

### Manual integration tests

- The full Starter Project acceptance scenario works with real applications.
- Reopening Starter Project produces another workspace instance.
- Permission denial for one application still allows later Resources to be attempted.
- Missing paths yield actionable errors.

## Phase 7: MVP hardening and documentation

Implementation status: managed Project storage, internal schema compatibility, and migration guidance are documented; the requirement-by-requirement verification baseline is recorded in `mvp-verification.md`. Permission recovery and final hardening checks remain.

### Outcomes

- Review the implementation against every product requirement and explicit non-goal.
- Document schema compatibility, managed storage, and legacy migration guidance.
- Document Automation and filesystem permissions and their recovery steps.
- Update `README.md` with verified build, test, and run instructions.
- Record implementation choices and known limitations in `IMPLEMENTATION_NOTES.md` without casually changing the north-star specification.
- Review accessibility, error language, launch responsiveness, and file integrity.

### Final verification

- Run all unit, repository integration, and UI tests.
- Perform a clean build and review every warning.
- Test first run with no managed Project library.
- Test valid and invalid internal Project data and legacy migration.
- Test an unknown Resource payload through load, display, save, and launch.
- Test Save/Discard/Cancel from every required trigger.
- Test real Safari, Terminal, and Finder integration under allowed and denied permissions.
- Inspect the final diff for unrelated changes, credentials, generated artifacts, and undocumented behavior.

## Deferred backlog

Do not pull these items into the MVP without a separate product decision:

- workspace capture;
- existing-window detection or reuse;
- AeroSpace tree-layout templates, including nested tile or accordion groups;
- additional enhanced browser or terminal adapters beyond Safari, Chrome, and
  Terminal.app;
- Terminal startup commands;
- live configuration watching or merge conflict handling;
- import, export, synchronization, or cloud storage;
- plugins, variables, dependencies, or conditional execution;
- AI, SSH, or Docker integrations;
- Project notes; and
- broad deployment-target support or App Store release work.

Reconsider tree-layout templates only if AeroSpace provides stable structured
inspection of the complete workspace tree and a deterministic, preferably
transactional, API for applying a layout to explicit window IDs. WorkBench
should not maintain an AeroSpace fork or reconstruct arbitrary trees through
focus-sensitive command sequences for this feature.

## Definition of done

The MVP is complete only when the requested behavior works, relevant automated tests pass, existing tests still pass, build warnings are reviewed, user-visible and architectural behavior is documented, and the resulting diff contains no unrelated changes.
