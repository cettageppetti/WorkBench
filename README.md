# WorkBench

WorkBench is a native macOS application for defining, saving, and opening complete working environments. Instead of launching applications one at a time, a user opens a Project composed of Resources such as Safari and Chrome windows, Terminal sessions, and Finder windows.

The MVP is intended first for its developer, while keeping the core Project–Resource model flexible enough for other Mac power users and software developers.

## Status

WorkBench has a native three-column SwiftUI editor, a versioned Project/Resource domain model, a tested JSON Project repository and draft workflow, and production Project launching for Safari, Chrome, Terminal, and Finder. MVP hardening and broader manual verification remain.

The MVP will answer one question: can a user describe a working environment as a collection of Resources and reliably recreate it with one action?

## MVP capabilities

- Create, rename, duplicate, delete, save, and open Projects.
- Add, edit, remove, and reorder Resources.
- Open Safari windows containing configured tabs.
- Open Chrome windows containing configured tabs.
- Open Terminal windows at configured directories.
- Open Finder windows at configured folders.
- Store one human-readable JSON file per Project in `~/Documents/WorkBench`.
- Request one-time access to that folder through the standard macOS folder picker and restore it with a security-scoped bookmark.
- Load hand-edited configuration files at launch or through the standard macOS **Reload Configurations** command.
- Report invalid files and unsupported Resource types without hiding them.
- Continue opening the remaining Resources when an individual Resource fails.

On first launch, WorkBench creates a **Starter Project** that opens:

- Safari with tabs for `apple.com` and `ibm.com`
- Terminal at `~/`
- Finder at `~/`

## Documentation

- [MVP design specification](docs/WorkBench_MVP_Design_Specification.md) — stable product vision and north star
- [Product requirements](docs/product-requirements.md) — testable MVP behavior and acceptance criteria
- [Architecture](docs/architecture.md) — technical boundaries and design decisions
- [Development plan](docs/development-plan.md) — phased implementation and verification plan
- [Configuration guide](docs/configuration.md) — schema version 1 and safe hand-editing guidance
- [MVP verification status](docs/mvp-verification.md) — automated, manual, and remaining acceptance coverage

The design specification should change only when the product vision changes. Implementation discoveries should be recorded separately as the codebase develops.

## Development environment

The verified initial development environment is Xcode 26.6, macOS SDK 26.5, and Swift 6.3.3. The active command-line developer directory points to the full Xcode toolchain. The deployment target is macOS 26.0; the MVP has no backward-compatibility requirement.

No third-party dependencies are planned for the MVP.

Build and run the complete signed test suite from the repository root:

```bash
xcodebuild test \
  -project WorkBench.xcodeproj \
  -scheme WorkBench \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WorkBenchSignedDerivedData
```

For a faster unsigned unit-test-only run, explicitly exclude the UI-test target:

```bash
xcodebuild test \
  -project WorkBench.xcodeproj \
  -scheme WorkBench \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WorkBenchUnitDerivedData \
  -only-testing:WorkBenchTests \
  CODE_SIGNING_ALLOWED=NO
```

Never use `CODE_SIGNING_ALLOWED=NO` for a run that includes
`WorkBenchUITests`; macOS rejects an unsigned UI-test runner as damaged.

## Scope

The MVP intentionally excludes workspace capture, window placement, additional browsers or terminals, synchronization, plugins, variables, conditional workflows, AI features, SSH, and Docker. See the product requirements for the complete list.
