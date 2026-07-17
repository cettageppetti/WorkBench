# WorkBench MVP Design Specification

## Overview

WorkBench is a native macOS application for defining, saving, and launching complete working environments.

Unlike traditional application launchers, WorkBench does not think in terms of applications.

It thinks in terms of **Projects**.

A Project represents a body of work.

Each Project is composed of one or more **Resources** that together define the user's working environment.

The objective is to reduce the cognitive effort required to resume work by recreating an entire workspace with a single action.

The MVP should establish the Project → Resource architecture while remaining intentionally small.

---

# Vision

Modern work is spread across many applications.

A software project may require:

- Safari
- Terminal
- Finder
- VS Code
- GitHub
- Documentation
- AI assistants

Today users manually recreate this environment every time they return to work.

WorkBench introduces a higher-level abstraction.

Instead of managing applications individually, WorkBench manages a reusable working environment.

The operating system manages windows.

Applications manage documents.

WorkBench manages Projects.

---

# What is a Project?

A Project is a reusable description of an entire working environment.

A Project is:

- named
- persistent
- declarative
- composed of Resources

A Project is **not**:

- a document
- an application
- a script

It is a description of what should exist when work begins.

Examples:

- AeroPeek Development
- Home Networking
- Investments
- Family Photos

Projects should be portable and persistent.

---

# What is a Resource?

A Resource is the fundamental building block of a Project.

A Resource represents anything WorkBench can:

- launch
- open
- create
- activate
- configure
- arrange (future)

Resources are intentionally independent.

Examples include:

- Browser Window
- Browser Tab
- Terminal Session
- Finder Window
- Document
- Folder
- Command
- Window Layout (future)
- SSH Session (future)
- Docker Container (future)

Projects are simply collections of Resources.

---

# Design Philosophy

## Projects are declarative

Projects describe the desired end state.

They never describe implementation steps.

Good:

> Open Safari with these tabs.

Not:

> Launch Safari, wait one second, create a window...

Implementation details belong inside WorkBench, not inside Project definitions.

## Resources are independent

Resources should know only about themselves.

Relationships should be explicit.

Loose coupling keeps the architecture extensible.

## Compose instead of special-case

The application should grow by adding new Resource types.

Avoid creating special features for individual workflows.

## Native macOS first

Use standard macOS conventions whenever possible.

WorkBench coordinates native applications.

It does not replace them.

## Human-readable configuration

Projects should be stored in a human-readable format.

Prefer YAML or JSON over binary databases.

The GUI edits the model.

Configuration files are the persistence layer.

## Simplicity wins

The MVP should contain the minimum functionality necessary to validate the Project → Resource model.

Everything else should wait until it solves a real problem.

## Optimize for resuming work

The purpose of WorkBench is not launching applications.

The purpose is helping users resume meaningful work with minimal effort.

---

# MVP Goal

The MVP exists to answer one question.

> Can users define a Project as a collection of Resources and reliably recreate that environment with a single action?

Nothing else matters yet.

---

# MVP Features

The MVP supports:

- Create Project
- Rename Project
- Delete Project
- Duplicate Project
- Add Resource
- Remove Resource
- Edit Resource
- Save Project
- Launch Project

Projects persist across application launches.

---

# Supported Resource Types

## Browser Window

Launch Safari.

Contains one or more tabs.

Properties:

- Name
- Tabs

## Terminal Session

Launch Terminal.app.

Properties:

- Name
- Working directory

Future property:

- Startup command

## Finder Window

Open a folder.

Properties:

- Name
- Folder path

---

# Explicitly Out of Scope

Do not implement:

- Workspace capture
- AeroSpace integration
- Window placement
- Window sizing
- Browser selection
- Terminal selection
- Plugins
- Variables
- Synchronization
- Import/export
- Dependency graphs
- Conditional execution
- AI integration
- SSH
- Docker

The MVP proves architecture—not features.

---

# User Workflow

1. Launch WorkBench.
2. Create a Project.
3. Give it a name.
4. Add Resources.
5. Configure Resources.
6. Save.
7. Click **Open**.
8. WorkBench recreates the workspace.

Opening the same Project multiple times simply creates another instance.

No attempt is made to reuse existing windows.

---

# Launch Behavior

Launching a Project should:

1. Validate the Project.
2. Launch every Resource.
3. Continue even if one Resource fails.
4. Present errors after launch.

A failure in one Resource should never prevent the remaining Resources from launching.

---

# Data Model

```
WorkBench
└── Projects
    └── Resources
        └── Resource Type
            └── Resource Properties
```

Conceptually:

```text
Project
    id
    name
    notes
    resources[]
```

```text
Resource
    id
    type
    name
    properties
```

Concrete resource types:

```text
BrowserWindowResource
    tabs[]
```

```text
TerminalSessionResource
    workingDirectory
```

```text
FinderWindowResource
    folder
```

The exact Swift implementation is intentionally left open.

Favor composition and protocol-oriented design so new Resource types can be added without redesigning the Project model.

---

# Persistence

Projects should be stored as individual files.

```
Projects/
    AeroPeek.yaml
    Networking.yaml
    Investments.yaml
```

One Project per file.

Configuration files should be:

- Human-readable
- Portable
- Easy to back up
- Suitable for version control

The GUI remains the primary editing experience.

---

# Example YAML

```yaml
name: AeroPeek

resources:

  - type: browser-window
    name: Documentation
    tabs:
      - https://github.com/
      - https://developer.apple.com/

  - type: terminal-session
    name: Build
    workingDirectory: ~/Projects/AeroPeek

  - type: finder-window
    name: Source
    folder: ~/Projects/AeroPeek
```

---

# User Interface

```
+----------------+-------------------+----------------------+
| Projects       | Resources         | Properties           |
|                |                   |                      |
| AeroPeek       | Browser Window    | Resource Settings    |
| Networking     | Terminal Session  |                      |
| Investments    | Finder Window     |                      |
|                |                   |                      |
| + Project      | + Resource        |                      |
+----------------+-------------------+----------------------+

                  [ Open Project ]
```

Use native SwiftUI controls.

Avoid unnecessary customization.

---

# Architecture

Future capabilities should be introduced as new Resource types rather than one-off features.

Examples:

- SSH Session
- Docker Container
- Database Connection
- AI Chat
- Window Layout
- Music Playlist
- Calendar

The Project model should remain unchanged.

---

# Success Criteria

The MVP is successful if a user can:

- Define a Project
- Save it
- Quit WorkBench
- Relaunch WorkBench
- Open the Project
- Have the expected applications appear

If this experience feels natural and reliable, the architecture has been validated.

---

# Long-Term Philosophy

WorkBench should be viewed as a **workspace orchestration framework**, not simply an application launcher.

The Project model is the product.

The GUI, launcher, and future integrations are clients of that model.

Everything should remain centered on three concepts:

- WorkBench
- Project
- Resource

Future capabilities should extend those concepts rather than replace them.
