# Winegold Native

Drop files to the right screen edge → pick an action → command runs locally.

macOS native app. 

## Stack

Swift + AppKit + SQLite + Foundation Process + XCTest

## Build

```bash
cd WinegoldNative
swift build --build-system native
```

> Note: the native build system is required if Xcode is not installed.
> An Xcode project is also supported (open `Package.swift` in Xcode).

## Run

```bash
./build-and-run.sh
```

The script builds, prepares the `.app` bundle, ad-hoc signs it, and opens it.

The app lives in the menu bar (no dock icon). Drag any file toward the right screen edge to open the action panel.

## Test

Requires Xcode (XCTest is not in Command Line Tools):

```bash
swift test
```

Or in Xcode: `⌘U`

## Create an action

Actions are stored in SQLite at `~/Library/Application Support/WinegoldNative/winegold.db`.

Default actions include:

| Action | Description | Binary |
|--------|-------------|--------|
| Print and clipboard | Print the full file path and copy it to clipboard | `/bin/zsh` |
| Ouvrir dossier | Open parent folder in Finder | `/usr/bin/open` |
| Install .add.yml script | Import a legacy `.add.yml` / `.yml` file as an action | internal importer |

To add more actions, use the Settings window action editor or import a supported `.add.yml` script.

For exact script support, see `../skills/winegold-native-scripts/SKILL.md`.

## Project structure

```
WinegoldNative/
├── Package.swift
├── Sources/
│   ├── CSQLite/          # system library module for sqlite3
│   ├── WinegoldCore/     # business logic (models, matcher, runner, storage)
│   └── WinegoldNative/   # UI (AppKit windows, panels, menu bar)
└── Tests/
    └── WinegoldNativeTests/  # XCTest unit tests
```

### Core modules

- **Action** – model (id, name, extensions, executable, args template)
- **ActionMatcher** – matches files to actions by extension
- **ActionTemplateResolver** – resolves `{input}`, `{basename}`, `{parent}`, etc.
- **ActionValidator** – checks executable exists and is executable
- **CommandRunner** – `Process`-based, async, stdout/stderr/exit code/timeout
- **Database** – SQLite wrapper (open, prepare, step, bind)
- **ActionStore** – CRUD for actions
- **RunHistoryStore** – persist and query run history

### UI modules

- **AppDelegate** – menu bar, DB init, wiring
- **EdgeCatcherWindow** – transparent edge window used to catch drags
- **ScreenEdgeService** – manages edge window per screen
- **ActionPanelWindow** – reusable singleton floating panel
- **ActionPanelViewController** – file list, action cards, results, history
- **ActionCardView** – individual clickable/drop action card
- **SettingsWindowController** – settings and action/script editor

## Security

- Commands run locally through Foundation `Process`.
- Imported/editor-created scripts run through `/bin/zsh -lc`.
- Timeout enforced on commands.
- No `sudo` in default actions.
- Be careful with imported scripts: review shell commands before running untrusted files.

## Current limitations

- Extension matching only, no UTI/MIME matching yet.
- No automatic folder watching triggers yet.
- Imported `.add.yml` supports only `name`, `trigger.fileExtension`, and `cmd.exec`.
- No `before`, `after`, `eval`, or `autolaunch` support yet.
- Multi-file drags are matched together, but command execution is still one file per run.
- No notification center integration yet.

## Roadmap

- Native `before.exec` / `after.open` / `after.notification` support.
- UTI matching.
- Automatic folder/file triggers.
- More preset actions: WebP, resize, PDF compress.
- Dark mode polish.

## License

MIT

## Agent skill

For agents creating or migrating Winegold Native scripts, see:

```txt
../skills/winegold-native-scripts/SKILL.md
```
