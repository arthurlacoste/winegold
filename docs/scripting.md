# Writing Winegold scripts

Winegold recipes are local YAML files ending in `.wg.yml`. They live under `~/.winegold/recipes/`, including ordinary nested category folders. Winegold watches this folder and keeps SQLite only as a derived index.

Legacy `.add.yml` files can still be imported. They are converted to `.wg.yml`; new recipes use only `.wg.yml`.

## Minimal example

```yml
id: winegold.copy-text-path
name: Copy text file path
description: Copy a text file path.
version: 1.0.0
enabled: true
trigger: extension equals "txt"
cmd:
  exec: 'printf "%s" "{input}" | pbcopy'
```

`trigger` is one readable expression. The same expression is used by imported recipes, the Settings builder, and direct expression editing.

## Multiple actions in one recipe

A recipe can expose several actions while sharing one trigger, variables, support files, and parent requirements:

```yml
id: winegold.node-project
name: Node project
description: Common Node.js project commands
trigger: kind equals "directory" and "package.json" exists
requires:
  commands:
    - npm
actions:
  - id: dev
    name: Start development server
    icon: play
    cmd:
      exec: 'cd "{input}" && npm run dev'

  - id: test
    name: Run tests
    description: Run the test suite.
    requires:
      commands:
        - node
    cmd:
      exec: |
        cd "{input}"
        npm test
    requiresConfirmation: true
    timeout: 0
```

Each child action requires a stable `id`, a `name`, and `cmd.exec`. Child IDs must match `[a-zA-Z0-9][a-zA-Z0-9._-]*`, be unique inside the recipe, and cannot contain `/`.

Winegold derives the runtime identity from the parent and child IDs, for example `winegold.node-project/test`. Renaming the visible action does not lose its identity. Changing its `id` creates a different action.

Parent requirements are merged with child requirements. Parent values provide the shared trigger and recipe context. Child values control the visible name, description, icon, command, success message, confirmation, timeout, and initial enabled state.

Legacy recipes with top-level `cmd` remain supported. When both `cmd` and `actions` exist, `actions` wins and Winegold reports a non-blocking warning.

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
{recipeDir}     absolute directory containing the `.wg.yml` file
```

Unavailable placeholders remain unchanged. Quote file paths in shell commands. Avoid injecting `{inside}` or `{text}` directly into shell syntax when content may be untrusted.

## YAML fields

Supported fields:

```txt
id
name
description
version
enabled
variables
trigger
cmd.exec
actions[].id
actions[].name
actions[].cmd.exec
actions[].description
actions[].icon
actions[].enabled
actions[].requires.commands
actions[].successMessage
actions[].requiresConfirmation
actions[].timeout
successMessage
files
requirements
```

`name` is required. Local recipes may omit `id`; Winegold generates one and writes it back atomically. Commands run with the recipe file's directory as their working directory.

`successMessage` is optional and appears only after success. Unknown YAML fields are ignored.

New recipes always use `.wg.yml` and expression triggers. Winegold still imports the older `trigger.fileExtension` list and normalizes it internally, but do not use that form for new scripts.

## Variables

Recipes can declare configurable variables that are injected as environment variables when the command runs. This keeps recipes clean and shareable without embedded tokens or machine-specific values.

```yml
variables:
  UPLOAD_ENDPOINT:
    label: Upload endpoint
    default: https://example.com/api.php

  UPLOAD_TOKEN:
    label: Service token
    secret: true
    required: true
    key: upload-service.token

cmd:
  exec: |
    curl -fsS \
      -H "Authorization: Bearer $UPLOAD_TOKEN" \
      -F "file=@{input}" \
      "$UPLOAD_ENDPOINT?format=url"
```

### Variable properties

| Property | Default | Description |
|----------|---------|-------------|
| `label` | derived from name | Human-readable label shown in Settings |
| `secret` | `false` | Store in macOS Keychain instead of SQLite |
| `required` | `false` | When `true`, missing value marks the recipe as "Needs setup" |
| `default` | (none) | Default value if not configured |
| `key` | (none) | Shared key for values used by multiple recipes |

### Value resolution

Non-secret variables resolve in order:

1. Winegold SQLite override
2. Environment inherited by the Winegold app
3. YAML `default`
4. missing

Secret variables resolve in order:

1. ~/.winegold/secrets.json value
2. Environment inherited by the Winegold app
3. missing

Do not assume variables configured in an interactive shell are available to an app launched from Finder.

### Setup state

If a required value is missing, the recipe is marked "Needs setup" and hidden from the action panel. It appears in Settings with configuration fields to complete. The recipe becomes available automatically once all required values are configured.

### Shared variables and consent

Recipes can share a stored value through `key`:

```yml
variables:
  OPENAI_API_KEY:
    label: OpenAI API key
    secret: true
    required: true
    key: openai.api-key
```

Two recipes may expose the same saved secret under different environment names. A newly installed recipe never gains silent access to an existing shared secret; a warning is shown requiring explicit approval.

### Privacy

- Secret values are never displayed in the UI, logs, history, or diagnostics
- Secret values are never included in exported recipes
- Commands are redacted with known secret values in output and error streams
- Use "Replace secret" rather than "Reveal secret"

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

## Installing recipes

Drag a `.wg.yml` file or a folder containing recipes into Winegold. Winegold shows a summary before installation, then copies the recipe into `~/.winegold/recipes/`; it never executes from the original location.

A standalone recipe gets its own folder. Relative helper references such as `resize.py` are copied from beside the recipe when found, and missing helpers produce a warning. Folder installation preserves ordinary nested files while skipping symlinks, hidden folders, dependency folders, caches, and build output.

Settings shows invalid recipe files and their parse errors. Use **Reveal** to locate the selected recipe or invalid file in Finder.


## Supporting files and requirements

A standalone recipe can declare local files that must be copied with it:

```yml
files:
  - scripts/resize.py
  - config/default.json
requirements:
  - python3
  - pillow>=10
```

Support paths must be relative to the recipe, stay inside its source folder, and cannot be symlinks. Winegold also detects common relative script references in `cmd.exec` and warns when they are missing or undeclared.

Recipe subfolders become local action categories. The category and manual display order stay in SQLite; they are not written into the recipe.

Settings updates known recipe fields atomically while preserving unknown top-level YAML fields, comments, version, declared files, requirements, and file permissions where practical. Use **Reveal** to open the source recipe in Finder.

## Published recipes and supporting files

Remote recipes use a stable `id` and `version`. They can declare required files and external commands:

```yml
id: winegold.resize-image
name: Resize image
description: Resize an image.
version: 1.0.0
enabled: true

trigger: extension in {"jpg" "jpeg" "png" "webp"}

files:
  - resize.py

requires:
  commands:
    - python3

cmd:
  exec: 'python3 resize.py "{input}"'
```

Supporting paths must be relative to the recipe directory. Absolute paths and `..` traversal are rejected. Every declared file is required. Remote installation downloads only declared files and an optional sibling `README.md`. Missing commands mark the recipe as needing setup. Winegold never installs dependencies automatically.


## Winegold Recipes catalogue index

A compatible repository can expose a JSON index over HTTPS:

```json
{
  "recipes": [
    { "url": "recipes/images/resize-image/resize-image.wg.yml" },
    { "url": "recipes/documents/md-to-pdf/md-to-pdf.wg.yml" }
  ]
}
```

URLs may be absolute or relative to the index. Each recipe remains autonomous and is installed atomically. Published metadata may include `author`, `category`, and `homepage` for the future Winegold Recipes browser.

Remote recipes stay linked to their source. Settings shows their source, installed version, local modification state, missing commands, and available updates. Updates are always manual. A locally modified recipe can be kept, replaced, or duplicated before updating. The duplicate receives a new local ID.

## Recipes without input

Omit `trigger` when a recipe does not need a file, folder, URL, or text input. These recipes appear in the global palette and run directly.

```yml
name: Clear local cache
cmd:
  exec: 'rm -rf "$HOME/Library/Caches/MyApp"'
```

A missing trigger means **no input**. It is different from `extension in {"*"}`, which still requires an input and accepts any extension.

When a palette recipe requires input, Winegold uses simple file or folder constraints to guide the native picker, then evaluates the complete trigger after selection. Complex conditions such as filename patterns, folder contents, metadata, or `inside` are validated after selection.
