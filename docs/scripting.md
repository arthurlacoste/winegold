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

Supported fields:

```yml
name: My action
trigger:
  fileExtension:
    - jpg
    - png
cmd:
  exec: 'echo "{input}"'
successMessage: 'Created {filename}'
```

```txt
name
trigger.fileExtension
cmd.exec
successMessage
```

`successMessage` is optional. It is displayed only when the command succeeds. It supports the same placeholders as `name` and `cmd.exec`. When omitted or empty, Winegold keeps the default completion message.

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

## Completion message

Use `successMessage` to replace the default `Done` label after a successful action:

```yml
name: Convert {filename}
trigger:
  fileExtension:
    - webp
cmd:
  exec: 'sips -s format jpeg "{input}" --out "{parent}/{basename}.jpg"'
successMessage: 'Created {basename}.jpg'
```

The message is not shown for failed, timed-out, or cancelled commands.

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

## Example: upload a file with curl and copy Markdown

This example uses an `uploadfile` server exposing `api.php`.

The endpoint accepts `multipart/form-data` with a file field named `file`.

It returns JSON by default. Add `?format=markdown`, `?format=url`, or `?format=html` to get plain text output for CLI scripts.

```yml
name: Upload file and copy Markdown
trigger:
  fileExtension:
    - jpg
    - jpeg
    - png
    - webp
    - gif
    - pdf
cmd:
  exec: 'curl -fsS -H "Authorization: Bearer CHANGE_ME_TO_A_SECRET_TOKEN" -F "file=@{input}" "https://example.com/api.php?format=markdown" | pbcopy'
```

Use the same one-line curl directly in a terminal:

```sh
curl -fsS -H "Authorization: Bearer CHANGE_ME_TO_A_SECRET_TOKEN" -F "file=@/absolute/path/file.png" "https://example.com/api.php?format=markdown"
```

## Script authoring tips

Keep commands short and explicit.

Quote every file path placeholder.

Use a YAML block scalar for multiline shell commands:

```yml
cmd:
  exec: |
    first command
    second command
```

Remember that Winegold runs `cmd.exec` with `/bin/zsh -lc`.

Avoid injecting `{inside}` directly into a shell argument when the file may contain quotes, HTML, JSON, dollar signs, backticks, or other shell syntax. Prefer reading `{input}` from Python, Node, or another tool and building the request payload safely.

Good for simple text:

```yml
cmd:
  exec: 'printf "%s" "{inside}" | pbcopy'
```

Safer for structured or multiline content:

```yml
cmd:
  exec: |
    python3 -c '
    from pathlib import Path
    print(Path("{input}").read_text())
    '
```

Use `&&` when the next step must run only after the previous command succeeds.

Use `|` when piping output into another command.

Write generated files with an absolute path based on `{parent}`:

```yml
cmd:
  exec: 'some-command "{input}" > "{parent}/{basename}.out.txt"'
```
