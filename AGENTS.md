# AGENTS.md

Cavemode notes for working on this repo.

## Project

Winegold Native is a macOS Swift app.

It catches dragged files/items at screen edges and shows a panel of actions.

## Commands

Use these before committing:

```bash
swift test
swift build --build-system native
```

To run the app:

```bash
./build-and-run.sh
```

## Repo map

```txt
Sources/WinegoldCore      core models, DB, matching, command execution
Sources/WinegoldNative    AppKit UI, panel, settings, drag handling
Tests/WinegoldNativeTests unit tests
docs                       user docs and product notes
```

## Rules

Keep UI copy in English.

Do not add big frameworks unless needed.

Prefer small commits.

If an issue number is mentioned in prompt, include it in the commit message.
Run tests before every commit.

Do not commit build artifacts.

Do not create automatic development reports or bilan files.

Keep test screenshots and PNG captures outside the repository, for example in `/tmp`.

Keep user scripts data-driven when possible.

When changing the script format, placeholders, importer, exporter, or other scripting core behavior, update `docs/scripting.md` in the same change.

## Main flows

Panel actions:

```txt
AppDelegate -> ActionPanelWindow -> ActionPanelViewController -> ActionCardView
```

Settings:

```txt
SettingsWindowController -> ActionStore
```

Command execution:

```txt
ActionTemplateResolver -> CommandRunner -> RunHistoryStore
```

Default actions live in:

```txt
Sources/WinegoldCore/DefaultActions.swift
```

## Common debug commands

```bash
DB="$HOME/Library/Application Support/WinegoldNative/winegold.db"
sqlite3 "$DB" "select name, enabled, accepted_extensions from actions order by name;"
tail -100 "$HOME/Library/Application Support/WinegoldNative/winegold.log"
```

## Style

Simple AppKit.

Small helpers.

No magic if a plain function is enough.

Keep the app local-first.
