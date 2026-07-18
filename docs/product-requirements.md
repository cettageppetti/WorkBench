# WorkBench MVP Product Requirements

## Purpose

WorkBench helps a Mac user resume meaningful work by recreating a saved working environment with one action. A working environment is represented by a Project containing an ordered collection of Resources.

This document translates the stable product vision in `WorkBench_MVP_Design_Specification.md` into testable MVP requirements. If the two documents conflict, the design specification remains the product north star until the conflict is resolved deliberately.

## Target user

The initial user is the application's developer: a Mac power user and software developer. The MVP should optimize for that user's real workflow without assuming that future users share the same applications, paths, or Projects.

Potential future users include Mac power users and software developers who repeatedly assemble application windows, websites, and folders to begin work.

## Product goals

1. Let the user define a Project as an ordered collection of independent Resources.
2. Persist Projects in a format that is readable and editable outside WorkBench.
3. Recreate each Project predictably with one action.
4. Isolate Resource failures so one failure does not prevent other Resources from opening.
5. Establish a model that can gain new Resource types without redesigning Project identity or persistence.

## MVP success criteria

The MVP succeeds when the user can:

1. Launch WorkBench and find a usable Starter Project.
2. Create or edit a Project and explicitly save it.
3. Quit and relaunch WorkBench without losing saved changes.
4. Open a Project and observe its supported Resources open sequentially in displayed order.
5. Understand and act on configuration, permission, validation, and launch failures.
6. Hand-edit a Project's JSON and load the change by relaunching WorkBench or choosing **Reload Configurations**.

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
- Standard application menus shall include **Reload Configurations** and **Quit** in appropriate conventional locations.

### First launch

- On first initialization, WorkBench shall ask the user to create or select `~/Documents/WorkBench` through a standard macOS folder-selection panel.
- WorkBench shall persist the granted access with an app-scoped security bookmark and restore it on later launches.
- If the bookmark is missing, stale, or denied, WorkBench shall explain the problem and ask the user to select the folder again.
- On the first initialization, if no saved Project configurations exist, WorkBench shall create and persist exactly one Project named **Starter Project**.
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
- Deleting a Project shall require confirmation before its JSON file is removed.
- Project deletion is complete only after the corresponding persisted file has been removed successfully.

### Resource management

- The user shall be able to add, select, edit, remove, and reorder Resources.
- Resource order shall be changed by drag and drop and persisted on Save.
- WorkBench shall offer Safari Window, Chrome Window, Terminal Session, and Finder Window Resource types.
- Removing a Resource modifies only the in-memory draft until the Project is saved.

### Explicit save and unsaved changes

- GUI edits shall remain in an in-memory draft until the user chooses **Save**.
- The UI shall clearly indicate when the selected Project has unsaved changes.
- Before switching Projects, closing the window, quitting, or reloading configurations with an unsaved draft, WorkBench shall offer **Save**, **Discard**, and **Cancel**.
- **Save** shall validate and persist before continuing the pending action.
- **Discard** shall restore the last loaded or saved representation before continuing.
- **Cancel** shall leave the draft and application state unchanged.
- A failed save shall cancel the pending destructive or navigational action and present the error.

### Persistence and manual editing

- WorkBench shall store one JSON file per Project under `~/Documents/WorkBench`.
- Each filename shall be based on the Project's stable identifier, not its friendly name.
- JSON shall be human-readable and use a documented, versioned schema.
- WorkBench shall use only home-relative paths beginning with `~` or absolute paths. Other relative paths are invalid.
- WorkBench shall expand `~` to the current user's home directory when resolving paths.
- Project files may be edited by hand while WorkBench is not using their contents as a draft.
- WorkBench shall load files at application launch and when the user chooses **Reload Configurations**.
- Live file watching and automatic mid-session reload are not required.
- Reload shall replace loaded data only after unsaved changes have been resolved.
- Invalid JSON or invalid Project data shall remain represented in the UI with a useful file-specific error rather than being skipped silently.
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
- After all Resources have been attempted, WorkBench shall present a consolidated summary when any Resource failed or was skipped.
- Opening the same Project multiple times shall create another workspace instance; WorkBench shall not search for or reuse existing windows.

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

- WorkBench shall enable App Sandbox.
- It shall request only the Documents-folder and application Automation access needed for MVP behavior.
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
- Window placement, sizing, or layout
- Browsers other than Safari and Google Chrome
- Terminals other than Terminal.app
- Startup commands
- Menu-bar status item behavior
- Live filesystem watching or conflict merging
- Project import, export, or synchronization
- Plugins, variables, dependencies, or conditional execution
- AeroSpace integration
- AI integration
- SSH or Docker Resources
- Project notes
- App Store distribution and broad backward-compatibility work

## MVP acceptance scenario

Given a clean first launch:

1. WorkBench asks the user to create or select `~/Documents/WorkBench` and persists access to it.
2. The Projects column shows **Starter Project**.
3. Its Resources column shows Safari, Terminal, and Finder in that order.
4. Choosing **Open Project** requests necessary permissions and then attempts each Resource sequentially.
5. Safari opens a new window with Apple and IBM tabs, Terminal opens at the user's home directory, and Finder opens the user's home directory.
6. After renaming or reordering a Resource, quitting prompts Save/Discard/Cancel.
7. Saving, quitting, and relaunching restores the saved state.
8. A valid hand edit is visible after relaunch or **Reload Configurations**.
9. An invalid JSON file remains visible with an actionable error.
10. An unknown Resource remains visible as unsupported while known Resources can still open.
