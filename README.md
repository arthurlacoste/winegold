<div align="center">
  <img src="docs/assets/winegold-logo.png" width="128" alt="Winegold icon">
  <h1>Winegold</h1>
  <p>Drop a file on the screen edge. Pick an action. Done.</p>
  <p>A native macOS app that runs commands locally.</p>
</div>

## Build

```bash
swift build --build-system native
```

The native build system works without Xcode. You can also open `Package.swift` in Xcode.

## Run

```bash
./build-and-run.sh
```

Winegold runs from the menu bar. Drag a file to the right screen edge to open the action panel.

## Test

Tests require Xcode:

```bash
swift test
```

Or press `⌘U` in Xcode.

## Recipe

Create actions from Settings or import a `.wg.yml` file.

```yml
name: Copy file path
trigger:
cmd:
  exec: 'echo "{input}" | pbcopy'
```

Recipes may omit `trigger` when they do not need input. Use an `input` block with `min` and `max` when an action requires a specific number of files or folders.

See [Writing Winegold scripts](docs/scripting.md) for the supported format, triggers, input rules, and placeholders.

## Releases and updates

Push a semantic version tag such as `v0.2.0`. GitHub Actions tests the app, builds the DMG and ZIP, publishes SHA-256 checksums, and creates the GitHub release.

Winegold checks the latest GitHub release once per day. Use **Check for Updates…** from the menu bar to check manually. Updates are downloaded from the tagged release, verified with SHA-256, installed over the current app, and relaunched.

## Security

Commands run locally. Imported scripts can execute shell commands, so review scripts before installing them.

## Limitations

Multi-file commands still run once per file.

## License

MIT
