# Writing Winegold scripts

Winegold scripts are small YAML files that create actions in the app.

Use the `.add.yml` extension.

Drag a `.add.yml` file into Winegold to import it.

## Minimal example

```yml
name: Copy file path
trigger:
  fileExtension:
    - txt
cmd:
  exec: 'echo "{input}" | pbcopy'
```

## Supported YAML

Only these fields are supported for now:

```yml
name: My action
trigger:
  fileExtension:
    - jpg
    - png
cmd:
  exec: 'echo "{input}"'
```

```txt
name
trigger.fileExtension
cmd.exec
```

Unsupported fields are ignored.

Imported scripts run as native actions with:

```txt
/bin/zsh -lc <cmd.exec>
```

## File extensions

Use one or more extensions:

```yml
trigger:
  fileExtension:
    - webp
    - png
```

Use `*` for all files:

```yml
trigger:
  fileExtension:
    - '*'
```

Write extensions without the dot.

## Placeholders

Winegold replaces these placeholders when the action runs:

```txt
{input}         full file path
{inputPath}     full file path, alias of {input}
{parent}        parent folder
{filename}      file name with extension
{basename}      file name without extension
{extension}     extension without dot
{dotExtension}  extension with dot
{inside}        UTF-8 file contents
{desktop}       Desktop folder
{downloads}     Downloads folder
{timestamp}     current timestamp, yyyy-MM-dd_HHmmss
```

Use these placeholders only.

## Quoting rules

Use single quotes around the YAML `exec` value.

Use double quotes around file path placeholders inside the shell command.

Good:

```yml
cmd:
  exec: 'cd "{parent}" && echo "{input}"'
```

For long commands, use a YAML block scalar:

```yml
cmd:
  exec: |
    cd "{parent}"
    echo "{input}"
```

## Example: convert WebP to JPEG

```yml
name: Convert WebP to JPEG
trigger:
  fileExtension:
    - webp
cmd:
  exec: 'cd "{parent}" && sips -s format jpeg "{input}" --out "{basename}.jpg"'
```

## Example: create a resized copy

```yml
name: Resize image to 1000px
trigger:
  fileExtension:
    - jpg
    - jpeg
    - png
    - webp
cmd:
  exec: 'cd "{parent}" && mkdir -p resized && sips -Z 1000 "{input}" --out "resized/{filename}"'
```

## Example: translate Markdown with Pi and Ollama

```yml
name: Translate MD to English with Pi
trigger:
  fileExtension:
    - md
cmd:
  exec: 'pi --print --no-session --no-approve --provider ollama --model gemma4:e2b --tools read,write "Read the Markdown file at this absolute path: {input}. Translate it to English. Write the translated Markdown to this absolute path: {parent}/{basename}.en.md."'
```

For long local AI commands, keep the command non-interactive.

Use flags like `--print`, `--no-session`, and `--no-approve` when the tool supports them.

## Tips

Keep commands short.

Quote file paths.

Use Settings to test a script by dropping a file into the test zone.

Use Export YAML to save an existing action as a script.

Use Help prompt to open ChatGPT with this documentation and the current action context.
