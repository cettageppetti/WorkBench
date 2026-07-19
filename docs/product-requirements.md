# WorkBench MVP Product Requirements

## Purpose

WorkBench helps a Mac user resume meaningful work by recreating a saved working environment with one action. A working environment is represented by a Project containing an ordered collection of Resources.

This document translates the stable product vision in `WorkBench_MVP_Design_Specification.md` into testable MVP requirements. If the two documents conflict, the design specification remains the product north star until the conflict is resolved deliberately.

## Target user

The initial user is the application's developer: a Mac power user and software developer. The MVP should optimize for that user's real workflow without assuming that future users share the same applications, paths, or Projects.

Potential future users include Mac power users and software developers who repeatedly assemble application windows, websites, and folders to begin work.

## Product goals

1. Let the user define a Project as an ordered collection of independent Resources.
2. Persist Projects in an application-managed, durable, versioned format.
3. Recreate each Project predictably with one action.
4. Isolate Resource failures so one failure does not prevent other Resources from opening.
5. Establish a model that can gain new Resource types without redesigning Project identity or persistence.

## MVP success criteria

The MVP succeeds when the user can:

1. Launch WorkBench and find a usable Starter Project.
2. Create or edit a Project and explicitly save it.
3. Quit and relaunch WorkBench without losing saved changes.
4. Open a Project and observe its supported Resources open sequentially in displayed order.
5. Understand and act on Project-data, permission, validation, and launch failures.

## Core concepts

### Project

A Project is a persistent, declarative description of a working environment. It has:

- a stable identifier;
- a required, unique, user-facing name; and
- an ordered collection of Resources.

Project notes are not part of the MVP.

### Resource

A Resource is an independently configurable item that WorkBench can open or activate. Every Resource has:

- a stable identifier;
- a type identifier;
- a user-facing name; and
- type-specific properties.

The order shown in the Resource list is the saved order and the launch order.

## Functional requirements

### Application shell

- WorkBench shall be a conventional single-window macOS application.
- It shall use the standard macOS application menu bar, not a menu-bar status item.
- The main window shall use the three-column organization from the design specification: Projects, Resources, and Properties.
- Standard application menus shall include **Reload Projects**, **Reveal Project Library**, and **Quit** in appropriate conventional locations.

### First launch

- WorkBench shall manage Projects under the current user's standard Application Support directory at `WorkBench/Projects`.
- WorkBench shall create the managed directory without requiring a folder-selection panel.
- When the managed library is empty and a former selected Project folder is available, WorkBench shall offer to copy its JSON Project files or start with an empty library.
- Migration shall never delete or modify the former Project folder and shall never overwrite a nonempty managed library.
- On the first initialization, if no saved Projects exist, WorkBench shall create and persist exactly one Project named **Starter Project**.
- WorkBench shall persist initialization state separately from the presence of Project files, so deleting Starter Project does not cause it to reappear.
- Starter Project shall contain, in order:

  1. a Safari Window with tabs for `https://apple.com` and `https://ibm.com`;
  2. a Terminal Session with working directory `~/`; and
  3. a Finder Window with folder `~/`.

### Project management

- The user shall be able to create, select, rename, duplicate, delete, save, and open a Project.
- Project names shall be nonempty after trimming whitespace and unique within WorkBench.
- A Project's stable identifier and filename shall not change when its friendly name changes.
- Duplicating a Project shall create new stable identifiers for the Project and its Resources and shall require or generate a unique friendly name.
- Deleting a Project shall require confirmation before its persisted data is removed.
- Project deletion is complete only after the corresponding persisted file has been removed successfully.

### Resource management

- The user shall be able to add, select, edit, remove, and reorder Resources.
- Resource order shall be changed by drag and drop and persisted on Save.
- WorkBench shall offer Safari Window, Chrome Window, Terminal Session, Finder
  Window, and generic Application Resource types.
- The user shall select a generic Application Resource through a standard
  macOS application picker. WorkBench shall persist its bundle identifier as
  primary identity and its selected path as a fallback location.
- Generic Application Resources shall use the application's normal macOS
  launch behavior; they do not promise to create a new window.
- Removing a Resource modifies only the in-memory draft until the Project is saved.

### Explicit save and unsaved changes

- GUI edits shall remain in an in-memory draft until the user chooses **Save**.
- The UI shall clearly indicate when the selected Project has unsaved changes.
- Before switching Projects, closing the window, quitting, or reloading Projects with an unsaved draft, WorkBench shall offer **Save**, **Discard**, and **Cancel**.
- **Save** shall validate and persist before continuing the pending action.
- **Discard** shall restore the last loaded or saved representation before continuing.
- **Cancel** shall leave the draft and application state unchanged.
- A failed save shall cancel the pending destructive or navigational action and present the error.

### Managed persistence

- WorkBench shall store one JSON file per Project under `~/Library/Application Support/WorkBench/Projects`.
- Each filename shall be based on the Project's stable identifier, not its friendly name.
- JSON is an internal persistence format and shall use a versioned schema; direct editing is unsupported.
- WorkBench shall use only home-relative paths beginning with `~` or absolute paths. Other relative paths are invalid.
- WorkBench shall expand `~` to the current user's home directory when resolving paths.
- WorkBench shall load files at application launch and when the user chooses **Reload Projects**.
- Live file watching and automatic mid-session reload are not required.
- Reload shall replace loaded data only after unsaved changes have been resolved.
- Invalid internal JSON or invalid Project data shall remain represented in the UI with a useful file-specific error rather than being skipped silently.
- An invalid Project shall not be launchable until repaired.
- WorkBench shall preserve unknown Resource objects without data loss, display them as unsupported, and allow the Project's known Resources to launch.
- Saving a Project containing unsupported Resources shall preserve their unknown JSON payloads unchanged except for formatting that does not alter data.

### Validation

- Validation messages shall identify the affected Project, Resource, property, or file where possible.
- Browser tab values shall be syntactically valid URLs. WorkBench shall not restrict URLs to `http` or `https`; any URL the selected Resource's browser supports is allowed.
- Terminal and Finder paths shall be either absolute or home-relative using `~`.
- A missing or inaccessible path is a launch-time Resource failure and shall not stop subsequent Resources.
- Duplicate stable identifiers, missing required fields, duplicate Project names, and unsupported schema versions shall be reported clearly.
- Unknown Resource types are unsupported, not invalid.

### Opening a Project

- **Open Project** shall validate the selected Project before launching Resources.
- Supported Resources shall launch sequentially in their displayed order.
- WorkBench shall wait for each Resource launch attempt to complete or fail before starting the next attempt.
- Failure of one Resource shall not prevent attempts to launch later supported Resources.
- Unsupported Resources shall be skipped and included in the result summary.
- A missing generic application shall fail only that Resource and shall not
  prevent later Resources from launching.
- After all Resources have been attempted, WorkBench shall present a consolidated summary when any Resource failed or was skipped.
- Opening the same Project multiple times shall create another workspace instance; WorkBench shall not search for or reuse existing windows.

### Planned AeroSpace launch destination

- A Project may optionally declare one AeroSpace workspace as its launch destination.
- The destination applies to the complete Project. Resource-specific destinations are deferred.
- A Project without a destination shall retain normal macOS and application window placement.
- WorkBench shall activate the configured AeroSpace workspace and wait for confirmation before launching any Resource.
- If activation fails, WorkBench shall launch no Resources until the user explicitly chooses **Open Without Placement**; **Cancel** shall leave the Project unopened.
- Activation failures include disabled integration, unavailable or stopped AeroSpace, connection or executable failure, timeout, and an AeroSpace command failure.
- After successful activation, WorkBench shall identify each window created by the launch, move that exact window to the destination, and confirm its reported workspace before continuing.
- WorkBench shall never move a window when the newly created window cannot be identified uniquely.
- A per-Resource placement failure shall be reported, shall not move an ambiguous candidate, and shall not prevent later Resources from being attempted.
- WorkBench shall restore focus to the destination workspace while Resources launch sequentially.
- Opening the same Project again shall reactivate its destination and create another set of Resource windows.
- AeroSpace integration shall be machine-specific and disabled until the user enables it in Settings.
- Disabling integration shall not erase destinations stored in Projects.
- The Project editor shall offer reported AeroSpace workspaces and permit manual workspace-name entry for offline editing and portability.
- WorkBench shall require a nonempty workspace name but shall treat AeroSpace as authoritative about availability at launch time.
- Project schema version 2 shall store the optional destination as a typed `launchDestination`; version 1 Projects shall load without a destination and upgrade only when saved.
- Unknown launch-destination types shall survive load/save without data loss and shall use the placement failure recovery flow rather than being ignored.
- Machine-specific enablement shall be stored outside Project JSON and shall default to disabled.
- WorkBench shall not edit AeroSpace configuration or override its workspace-to-monitor assignments, layouts, or keyboard bindings.
- For a Project with an explicit destination, WorkBench placement shall override global application routing and `on-window-detected` workspace moves only for windows created by that launch.
- Named native macOS Spaces shall not be supported; WorkBench shall not use private APIs or UI scripting to manipulate them.

### Supported Resource behavior

#### Safari Window

- Opens a new Safari window.
- Opens its configured tabs in saved order.
- Supports one or more tabs.
- Reports malformed URLs, denied Automation permission, Safari launch failures, and scripting failures.

#### Chrome Window

- Opens a new Google Chrome window.
- Opens its configured tabs in saved order.
- Supports one or more tabs.
- Reports malformed URLs, denied Automation permission, Chrome launch failures, and scripting failures.

#### Terminal Session

- Opens a new Terminal window.
- Sets its initial working directory to the configured resolved path.
- Does not run a startup command in the MVP.
- Reports invalid or inaccessible paths, denied Automation permission, Terminal launch failures, and scripting failures.

#### Finder Window

- Opens a Finder window showing the configured resolved folder.
- Reports invalid or inaccessible folders, denied required permission, Finder launch failures, and scripting failures.

### Permissions and privacy

- WorkBench shall run outside App Sandbox because its planned AeroSpace integration requires local CLI or Unix-socket access that the sandbox blocks.
- It shall retain Hardened Runtime and request only application Automation consent needed for MVP behavior.
- The app shall explain why Automation access is needed when macOS prompts the user.
- Permission denial shall not crash the app or stop unrelated Resources from launching.
- Permission errors shall name the affected application and give the user a useful recovery direction.
- WorkBench shall not collect telemetry, synchronize data, or transmit Project configurations in the MVP.

## Nonfunctional requirements

- The UI shall use native SwiftUI controls and standard macOS conventions.
- The application shall remain responsive during Resource launching and file operations.
- File writes shall avoid leaving partially written Project files.
- Domain and persistence behavior shall be testable without launching external applications.
- Application integrations shall be isolated behind interfaces so they can be replaced with test doubles.
- The MVP shall add no third-party dependencies.
- User-visible failures and build warnings shall be reviewed rather than suppressed.

## Explicitly out of scope

- Capturing the current workspace
- Detecting or reusing existing application windows
- AeroSpace tree-layout templates or per-window sizing beyond assigning created
  windows to a Project's AeroSpace workspace
- Enhanced browser-window adapters other than Safari and Google Chrome
- Enhanced terminal-session adapters other than Terminal.app
- Startup commands
- Menu-bar status item behavior
- Live filesystem watching or conflict merging
- Project import, export, or synchronization
- Plugins, variables, dependencies, or conditional execution
- Resource-specific AeroSpace workspace overrides
- AI integration
- SSH or Docker Resources
- Project notes
- App Store distribution and broad backward-compatibility work

## MVP acceptance scenario

Given a clean first launch:

1. WorkBench creates its managed Project library in Application Support; if a former selected library exists, it offers a copy-based import or a clean start.
2. The Projects column shows **Starter Project**.
3. Its Resources column shows Safari, Terminal, and Finder in that order.
4. Choosing **Open Project** requests necessary permissions and then attempts each Resource sequentially.
5. Safari opens a new window with Apple and IBM tabs, Terminal opens at the user's home directory, and Finder opens the user's home directory.
6. After renaming or reordering a Resource, quitting prompts Save/Discard/Cancel.
7. Saving, quitting, and relaunching restores the saved state.
8. **Reload Projects** preserves the normal unsaved-change decision before reloading managed data.
9. Invalid internal Project data remains visible with an actionable error.
10. An unknown Resource remains visible as unsupported while known Resources can still open.
