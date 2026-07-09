# Writing Winegold scripts

Winegold scripts are small YAML files that create actions in the app.

Use the `.add.yml` extension.

## Minimal example

```yml
name: Copy file path
trigger:
  fileExtension:
    - txt
cmd:
  exec: 'echo "{{file}}" | pbcopy'
```

Drag this file into Winegold to import it.

## Supported fields

```yml
name: My action
trigger:
  fileExtension:
    - jpg
    - png
cmd:
  exec: 'echo "{{file}}"'
```

Only these fields are supported for now:

```txt
name
trigger.fileExtension
cmd.exec
```

Unsupported fields are ignored.

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

## Placeholders

Winegold converts these placeholders when the action runs:

```txt
{{file}}       full file path
{{dir}}        parent folder
{{name}}       file name with extension
{{namebase}}   file name without extension
{{ext}}        extension with dot
{{inside}}     UTF-8 file contents
{{desktop}}    Desktop folder
{{downloads}}  Downloads folder
{{timestamp}}  current timestamp
```

Native actions also support the same values with braces:

```txt
{input}
{parent}
{filename}
{basename}
{extension}
{dotExtension}
{inside}
{desktop}
{downloads}
{timestamp}
```

## Example: convert WebP to JPEG

```yml
name: Convert WebP to JPEG
trigger:
  fileExtension:
    - webp
cmd:
  exec: 'cd "{{dir}}" && sips -s format jpeg "{{file}}" --out "{{namebase}}.jpg"'
```

## Example: summarize a text file with Ollama

```yml
name: Summarize text
trigger:
  fileExtension:
    - txt
    - md
cmd:
  exec: 'ollama run llama3.2 "Summarize this: {{inside}}"'
```

## Tips

Keep commands short.

Quote file paths.

Use Settings to test a script by dropping a file into the test zone.

Use Export YAML to save an existing action as a script.

Use Help prompt to open ChatGPT with the current action context.
