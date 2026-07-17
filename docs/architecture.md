# WorkBench MVP Architecture

## Architecture goals

The MVP architecture should make the Project–Resource model explicit, keep macOS integrations replaceable and testable, and preserve human-editable configuration data safely. It should not build a plugin framework or generalized orchestration engine before the MVP validates the product.

The intended structure is a small native SwiftUI application with a domain layer, JSON persistence, and isolated application launch adapters.

## Constraints and decisions

- Native macOS application using Swift and SwiftUI.
- Initial development with Xcode 26.6, macOS SDK 26.5, and Swift 6.3.3; the exact deployment target will be chosen when the Xcode project is created.
- Swift strict concurrency should be enabled from the beginning.
- No third-party dependencies.
- App Sandbox enabled.
- Project files stored in a user-selected `~/Documents/WorkBench` folder using user-selected read/write access and an app-scoped security bookmark.
- Apple Events/Automation used where exact Safari, Terminal, or Finder window behavior requires it.
- JSON encoded and decoded with Foundation `Codable` facilities where compatible with lossless unknown-Resource preservation.

## System context

```text
User
  |
  v
WorkBench SwiftUI application
  |-- reads/writes --> ~/Documents/WorkBench/*.json
  |-- automates ----> Safari
  |-- automates ----> Terminal.app
  `-- opens/automates -> Finder
```

WorkBench owns Project definitions and launch coordination. macOS owns permissions and window management. Safari, Terminal, and Finder remain responsible for their own content and behavior.

## Internal boundaries

### Presentation

SwiftUI views present Projects, Resources, editable properties, validation messages, launch results, and standard dialogs. A single application-state owner coordinates selection, drafts, dirty state, and menu commands.

Views should not read files, encode JSON, send Apple Events, or directly launch applications.

### Application workflows

Use small workflow types or methods for user actions such as:

- bootstrap Projects;
- select a Project;
- save or discard a draft;
- reload configurations;
- create, duplicate, rename, and delete Projects;
- mutate and reorder Resources; and
- open a Project.

This layer enforces prompt and sequencing rules while delegating storage and external application work through protocols.

### Domain model

The domain contains Project identity, names, ordered Resources, validation results, and launch results. It must not depend on SwiftUI or Apple Events.

Conceptually:

```text
Project
  id: ProjectID
  name: String
  resources: [Resource]

Resource
  id: ResourceID
  name: String
  payload:
    browserWindow(tabs)
    terminalSession(workingDirectory)
    finderWindow(folder)
    unsupported(type, rawObject)
```

Project and Resource identifiers should wrap UUID values to prevent accidental interchange. The Resource array is authoritative for display and launch order.

Unsupported Resources are first-class loaded values. Their original JSON object must be retained so opening or saving with a newer configuration does not discard fields an older WorkBench version cannot interpret.

### Persistence

A Project repository abstracts directory creation, discovery, decoding, validation, atomic saving, deletion, and bootstrap state. Presentation code consumes repository results rather than filesystem APIs.

The repository should return both valid Projects and file-level load failures so the UI can represent malformed files. It should not silently omit files.

Writes should be atomic: encode to a temporary sibling file and replace the destination through a Foundation API that provides atomic behavior. A failed write must leave the last saved configuration usable.

The application loads configurations:

- during startup; and
- after the **Reload Configurations** command resolves any dirty draft.

Live filesystem observation is out of scope.

### Launching

A Project launcher validates a Project and dispatches each supported Resource to its matching launcher adapter sequentially. Each attempt returns a structured result rather than terminating the overall operation.

```text
Open Project
  -> validate Project
  -> for each Resource in order
       -> unsupported: record skipped
       -> supported: await matching launcher result
       -> record success or failure
  -> return consolidated LaunchReport
```

Suggested boundaries are `BrowserLaunching`, `TerminalLaunching`, and `FinderLaunching`. Production adapters communicate with macOS; test doubles return deterministic outcomes.

Apple Events and scripting details belong inside the adapters. The architecture does not expose scripts as part of the Project model because Projects describe desired state, not implementation steps.

## JSON configuration schema

The schema should be documented and versioned before persistence code is considered complete. A representative shape is:

```json
{
  "schemaVersion": 1,
  "id": "3B06EC67-9A7C-4D66-ACF4-3F869F195C1F",
  "name": "Starter Project",
  "resources": [
    {
      "id": "0D97C7AD-7060-4BB3-B78D-79265770D454",
      "type": "browser-window",
      "name": "Web",
      "tabs": [
        "https://apple.com",
        "https://ibm.com"
      ]
    },
    {
      "id": "BD7DB95B-C3C7-4B5A-A14D-E1E232CB9D34",
      "type": "terminal-session",
      "name": "Home Terminal",
      "workingDirectory": "~/"
    },
    {
      "id": "C8600B47-A793-4C62-8243-B964F75EE726",
      "type": "finder-window",
      "name": "Home Folder",
      "folder": "~/"
    }
  ]
}
```

The filename is `<project-id>.json`. A rename changes `name`, not the filename or identifier.

Decoding should occur in two stages:

1. Decode and validate the Project envelope and each Resource's common fields and type discriminator.
2. Decode known type-specific payloads; retain the complete object representation for unknown types.

Foundation's generic JSON value handling may be needed for unknown payloads because a plain synthesized `Codable` enum would discard unrecognized shapes. This should be implemented locally rather than by adding a dependency.

Schema versions newer than the app supports are Project-level errors unless a future migration policy explicitly makes them readable. Version migrations are not needed until a second schema exists.

## Draft and state model

Loaded persisted data and the currently edited draft should be distinct values. Dirty state should derive from comparison with the last loaded/saved value rather than a collection of manually maintained flags where practical.

Only one Project draft needs to be active in the single-window MVP. Navigation, reload, window close, and termination all pass through one unsaved-changes coordinator implementing Save/Discard/Cancel consistently.

A successful save replaces the persisted snapshot and clears dirty state. A failed save keeps the draft and selection unchanged.

## Validation strategy

Validation has three levels:

1. **Decode validation:** valid JSON, expected primitive types, supported schema version, and required envelope fields.
2. **Domain validation:** unique Project names and identifiers, nonempty names, valid Resource identifiers, valid URLs, and permitted path forms.
3. **Launch validation:** path existence and accessibility, external application availability, and current Automation permission.

An unknown Resource type passes decode and domain validation as unsupported. It is skipped at launch and included in the LaunchReport.

Path resolution expands a leading `~` using the current user's home directory. Only `~`-based and absolute paths are accepted; no working-directory-relative interpretation is allowed.

## macOS integration and permissions

The app should use the narrowest reliable system interface for each Resource. Finder may be opened through workspace APIs when they guarantee the required behavior; Apple Events should be used only when a new, specifically configured window cannot otherwise be guaranteed.

Safari and Terminal integration will likely require Automation access. The Xcode target will need appropriate sandbox entitlements and usage descriptions. Permission denial is a normal adapter failure, not a fatal application error.

The Phase 1 spike confirmed that Safari, Terminal, and Finder do not expose public sandbox scripting access groups sufficient for the MVP operations. In addition to the hardened-runtime Apple Events entitlement and usage description, the sandboxed MVP uses temporary Apple Event exceptions limited to those three bundle identifiers. This creates a future Mac App Store review risk and must be reassessed before distribution.

Before the main UI is built out, a technical spike should verify:

- a sandboxed app can establish durable access to `~/Documents/WorkBench` under the intended distribution model;
- Safari can open a new window with ordered tabs;
- Terminal can open a new window at a resolved directory;
- Finder can reliably open the required folder in a window; and
- denied or revoked Automation access produces actionable errors.

The filesystem spike confirmed that App Sandbox has no fixed Documents-folder entitlement. The approved first-run flow uses a standard folder-selection panel and persists an app-scoped security bookmark. Missing, stale, or denied bookmarks return the app to folder selection without replacing configurations.

## Concurrency

UI state changes run on the main actor. File and external application operations should use asynchronous APIs or isolated workers so the UI remains responsive.

Project launching is deliberately sequential even though its API is asynchronous. The launcher awaits each adapter before proceeding. Shared mutable state should be avoided; results are accumulated into an immutable or actor-isolated LaunchReport.

## Error model

Errors should be structured for both testing and user presentation. Major categories are:

- configuration discovery, read, decode, validation, write, and delete failures;
- duplicate names or identifiers;
- unsupported schema versions or Resource types;
- inaccessible or nonexistent paths;
- unavailable applications;
- denied Automation or filesystem permission; and
- external application scripting failures.

Low-level errors may be retained for diagnostics, but the UI should display a concise description, affected item, and recovery suggestion when one exists.

## Testing architecture

### Unit tests

- Project and Resource validation
- Path parsing and `~` expansion
- JSON round trips for supported Resources
- Lossless round trips for unsupported Resources
- Schema-version handling
- Unique-name and identifier detection
- Starter Project construction
- Draft dirty-state transitions
- Launch sequencing and failure isolation using test adapters

### Repository integration tests

Use temporary directories to test discovery, atomic saving, deletion, malformed files, duplicate configurations, and reload behavior without touching the user's Documents directory.

### UI tests

Cover the Starter Project, Project and Resource editing, drag reordering, explicit save, unsaved-change prompts, invalid-file presentation, and launch-result presentation with external adapters substituted or placed in a controlled test mode.

### Manual integration tests

Automation permission prompts and real Safari, Terminal, and Finder behavior require manual verification on a clean permission state. These checks supplement rather than replace automated domain and workflow tests.

## Deferred architectural concerns

The MVP should not introduce a plugin API, dependency graph, generic command runner, window-layout engine, synchronization subsystem, or migration framework. Protocol boundaries around Resource launching and persistence provide sufficient seams for current testing and likely extensions.

Implementation discoveries and deviations should be recorded in a future `IMPLEMENTATION_NOTES.md` as requested by `DIRECTION.md`; the stable design specification should change only when product vision changes.
