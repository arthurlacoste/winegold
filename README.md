# Winegold

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

## Release builds

GitHub Actions validates pull requests and every push to `main`.

- Pull requests run tests and a release build without publishing an artifact.
- Pushes to `main` and manual workflow runs produce a downloadable ZIP artifact.
- Tags matching `vMAJOR.MINOR.PATCH`, such as `v0.2.0`, also create a GitHub Release and attach the ZIP.

Create a release with:

```bash
git tag -a v0.2.0 -m "Winegold v0.2.0"
git push origin v0.2.0
```

The tag controls `CFBundleShortVersionString`. GitHub Actions uses its run number for `CFBundleVersion`.

Build and package the same unsigned release locally with:

```bash
VERSION=0.2.0 BUILD_NUMBER=2 scripts/build-app.sh
scripts/package-release.sh
```

Current packages are ad-hoc signed but not Apple-notarized. macOS Gatekeeper may warn after downloading the ZIP. In Finder, Control-click the app and choose **Open** to approve it manually.

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

- No automatic folder watching triggers yet.
- `inside` supports UTF-8 local files up to 1 MiB; no PDF/DOCX extraction or OCR.
- Imported `.add.yml` supports `name`, expression `trigger`, `cmd.exec`, and `successMessage`.
- No `before`, `after`, `eval`, or `autolaunch` support yet.
- Multi-file drags are matched together, but command execution is still one file per run.
- No notification center integration yet.

## Roadmap

- Native `before.exec` / `after.open` / `after.notification` support.
- Automatic folder/file triggers.
- More preset actions: WebP, resize, PDF compress.
- Dark mode polish.

## License

MIT

## Agent skill

For agents creating or migrating Winegold scripts, see:

```txt
../skills/winegold-native-scripts/SKILL.md
```
