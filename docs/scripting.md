# Writing Winegold scripts

Winegold scripts are local YAML files ending in `.add.yml`. Drag one into Winegold or import it from Settings.

## Minimal example

```yml
name: Copy text file path
trigger: extension equals "txt"
cmd:
  exec: 'printf "%s" "{input}" | pbcopy'
```

`trigger` is one readable expression. The same expression is used by imported/exported scripts, the Settings builder, and direct expression editing.

## Nested expressions

```yml
name: Find notes or URLs
trigger: >
  isURL or
  (extension in {"md" "txt"} and inside contains "TODO")
cmd:
  exec: 'printf "%s" "{input}"'
successMessage: 'Matched {kind}'
```

Use parentheses with `and`, `or`, and `not`:

```txt
not (extension equals "png" or size greaterThan 1000000)
```

Matching is case-insensitive unless the operator ends in `Case`.

## Fields

Common fields and matching placeholders share names:

```txt
input parent parentName filename basename extension dotExtension
inside desktop downloads timestamp
kind mimeType uti size finderTags
url scheme host urlPath query fragment
text
```

Boolean shortcuts:

```txt
isFile isDirectory isURL isText
```

`kind` is `file`, `directory`, `url`, or `text`. A field unavailable for the dragged item makes its condition `false`. `inside` reads only UTF-8 local files up to 1 MiB. It never downloads URL contents. PDF, DOCX, OCR, and other extraction are not performed.

URL drags keep the raw URL. Plain dragged text is available through `text`; it is not treated as file contents.

## Operators

```txt
equals contains startsWith endsWith matches
in notIn exists
greaterThan greaterThanOrEqual lessThan lessThanOrEqual
equalsCase containsCase startsWithCase endsWithCase
```

Examples:

```txt
extension in {"jpg" "jpeg" "png"}
filename matches /TODO-[0-9]+/i
finderTags contains "review"
size lessThanOrEqual 5000000
host endsWith "example.com"
kind equals "directory"
```

## Commands and placeholders

Winegold runs `cmd.exec` as `/bin/zsh -lc <command>`.

```txt
{input}         path for files/directories, raw value for URL/text
{inputPath}     local execution path
{parent}        parent folder
{parentName}    parent folder name
{filename}      file name with extension
{basename}      file name without extension
{extension}     extension without dot
{dotExtension}  extension with dot
{inside}        UTF-8 file contents, maximum 1 MiB
{kind}          file, directory, url, or text
{mimeType}      MIME type when available
{uti}           Uniform Type Identifier when available
{size}          file size in bytes
{finderTags}    comma-separated Finder tags
{url}           raw dragged URL
{scheme} {host} {urlPath} {query} {fragment}
{text}          raw dragged text
{desktop} {downloads} {timestamp}
```

Unavailable placeholders remain unchanged. Quote file paths in shell commands. Avoid injecting `{inside}` or `{text}` directly into shell syntax when content may be untrusted.

## YAML fields

Supported fields:

```txt
name
trigger
cmd.exec
successMessage
```

`successMessage` is optional and appears only after success. Unknown YAML fields are ignored.

New exports always use expression triggers. Winegold still imports the older `trigger.fileExtension` list and normalizes it internally, but do not use that form for new scripts.

## Examples

Convert images:

```yml
name: Convert image to JPEG
trigger: extension in {"webp" "png"}
cmd:
  exec: 'sips -s format jpeg "{input}" --out "{parent}/{basename}.jpg"'
```

Open a dragged URL host:

```yml
name: Copy example URL
trigger: isURL and host endsWith "example.com"
cmd:
  exec: 'printf "%s" "{url}" | pbcopy'
```

Process small Markdown notes:

```yml
name: Process TODO note
trigger: extension equals "md" and size lessThan 1048576 and inside contains "TODO"
cmd:
  exec: |
    cd "{parent}"
    printf "%s\n" "{filename}"
```
