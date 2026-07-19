# WorkBench Configuration Guide

WorkBench stores each Project as a human-readable JSON file in the configuration directory selected on first launch. For the MVP, select `~/Documents/WorkBench`. The app remembers that directory with a standard macOS bookmark.

## Editing safely

Quit WorkBench before editing a Project file by hand, or save/discard any GUI edits first. WorkBench reads external changes at launch and when **WorkBench > Reload Configurations** is chosen; it does not watch files continuously. Reloading while the current Project has unsaved GUI edits presents the normal Save/Discard/Cancel prompt.

Use a JSON-aware editor and keep the file as valid UTF-8 JSON. WorkBench writes formatted JSON with sorted keys when it saves. Invalid files remain visible in the interface with a file-specific error instead of being silently ignored.

Each filename must be the Project's lowercase UUID followed by `.json`. For example, a Project whose `id` is `3B06EC67-9A7C-4D66-ACF4-3F869F195C1F` must be stored as:

```text
3b06ec67-9a7c-4d66-acf4-3f869f195c1f.json
```

Renaming a Project means changing its `name`; do not change its `id` or filename. To create a Project by copying JSON, generate new UUIDs for the Project and every Resource, then rename the file to match the new Project UUID.

## Schema version 2

A complete Project has this shape:

```json
{
  "id": "3B06EC67-9A7C-4D66-ACF4-3F869F195C1F",
  "launchDestination": {
    "type": "aerospace-workspace",
    "workspace": "2"
  },
  "name": "Starter Project",
  "resources": [
    {
      "id": "0D97C7AD-7060-4BB3-B78D-79265770D454",
      "name": "Web",
      "tabs": [
        "https://apple.com",
        "https://ibm.com"
      ],
      "type": "browser-window"
    },
    {
      "id": "BD7DB95B-C3C7-4B5A-A14D-E1E232CB9D34",
      "name": "Home Terminal",
      "type": "terminal-session",
      "workingDirectory": "~/"
    },
    {
      "folder": "~/",
      "id": "C8600B47-A793-4C62-8243-B964F75EE726",
      "name": "Home Folder",
      "type": "finder-window"
    }
  ],
  "schemaVersion": 2
}
```

Project fields:

| Field | Requirement |
| --- | --- |
| `schemaVersion` | Required integer. Supported values are `1` and `2`; WorkBench writes `2`. |
| `id` | Required UUID, unique across all Projects. Determines the filename. |
| `name` | Required nonempty string, unique ignoring case and surrounding whitespace. |
| `launchDestination` | Optional object. When absent, WorkBench uses normal window placement. |
| `resources` | Required array. Its order is the launch order. It may be empty. |

The supported launch destination has `type` set to `aerospace-workspace` and a
nonempty `workspace` string. Workspace names are case-sensitive and are passed
to AeroSpace exactly as stored. The Project editor trims surrounding whitespace
from user-entered names, while hand-edited names containing only whitespace are
invalid.

An otherwise valid destination with an unknown `type` is preserved without data
loss but cannot be activated. Opening that Project follows the normal placement
failure flow: no Resource launches until the user chooses **Open Without
Placement**, or the user may cancel.

Every Resource requires a UUID `id`, a nonempty `name`, and a string `type`. Resource UUIDs must be unique within their Project.

Supported Resource payloads:

| `type` | Required payload | Behavior |
| --- | --- | --- |
| `browser-window` | `tabs`: nonempty array of URL strings with schemes | Opens one new Safari window with tabs in array order. Any URL scheme Safari supports is allowed. |
| `chrome-window` | `tabs`: nonempty array of URL strings with schemes | Opens one new Google Chrome window with tabs in array order. Any URL scheme Chrome supports is allowed. |
| `terminal-session` | `workingDirectory`: path string | Opens one new Terminal window and explicitly changes to the resolved directory. |
| `finder-window` | `folder`: path string | Opens one new Finder window showing the resolved directory. |

Terminal and Finder paths must be absolute, `~`, or begin with `~/`. WorkBench expands `~` to the macOS login account's home directory. A Terminal session stored as exactly `~` or `~/` opens with Terminal's normal profile startup behavior and does not inject a `cd` command; all other Terminal paths are enforced with an explicit directory change. Other relative paths and named-user forms such as `~someone/Projects` are invalid. Path existence and directory accessibility are checked when the Project is opened, not when it is decoded.

## Unknown Resource types

An otherwise valid Resource with an unknown `type` is unsupported rather than invalid. WorkBench preserves its complete JSON object when loading and saving, displays it as unsupported, skips it during launch, and continues launching known Resources. This permits future Resource types to survive round trips through an older WorkBench version.

### Version 1 compatibility

Version 1 files remain readable and behave as if `launchDestination` were
absent. WorkBench does not rewrite files merely because it loaded them. The next
save writes schema version 2. Versions newer than 2 remain unreadable so an
older WorkBench cannot silently discard fields it does not understand.

## Editing AeroSpace destinations

Open **WorkBench > Settings** to enable the machine-local AeroSpace integration
and check whether WorkBench can list workspaces. This preference is not written
to Project JSON.

Select **Project Settings** above the Resource list to choose normal window
placement or an AeroSpace workspace. The workspace field accepts manual names
even when AeroSpace is unavailable. **Refresh Workspaces** adds the names
reported by the current machine to a choice menu without replacing the manual
value. Save the Project to persist its destination.

When a Project has an AeroSpace destination, WorkBench places each window it
creates into that workspace. This explicit Project placement overrides a global
`on-window-detected` workspace rule for that new window only; it does not edit
the AeroSpace configuration or move unrelated windows. WorkBench reports a
Resource failure and moves nothing if it cannot identify exactly one new
window. It continues with later Resources and attempts to restore focus to the
Project workspace.

## Resolving errors

When a file is reported as invalid:

1. Read the file-specific message in WorkBench.
2. Correct the JSON, required fields, UUIDs, filename, or validation issue in an editor.
3. Save the file.
4. Choose **WorkBench > Reload Configurations** or relaunch WorkBench.

WorkBench does not rewrite an invalid file automatically.
