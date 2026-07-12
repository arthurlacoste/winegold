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

See [Writing Winegold scripts](docs/scripting.md) for the supported format, triggers, and placeholders.

## Security

Commands run locally. Imported scripts can execute shell commands, so review scripts before installing them.

## Limitations

Multi-file commands still run once per file.

## License

MIT
