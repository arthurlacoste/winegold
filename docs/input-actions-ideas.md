# Winegold input actions ideas

Winegold should not only be a file action launcher.

The stronger idea is:

```txt
Drag anything -> choose what it becomes.
```

A dragged item can be a file, an image, a URL, selected text, a web element, HTML, or an image coming from a browser. Winegold can detect the input type, show relevant actions, and let the user transform it into a note, a bookmark, a prompt, a local action, or a processed file.

## Product split

Winegold should keep a clean separation between generic app features and personal workflows.

```txt
1. Built-in core
2. Optional action packs
3. Personal scripts
```

## Built-in core

The built-in layer should stay universal, stable, and useful for everyone.

Examples:

```txt
Open parent folder
Reveal in Finder
Copy path
Copy filename
Import YAML
Export YAML
Convert image
Resize image
Open URL
Download URL
Send to ChatGPT
Save text to file
```

The built-in core makes the app useful immediately after install.

## Optional action packs

Action packs are groups of actions that can be enabled or disabled.

Examples:

```txt
Web Pack
Text Pack
Image Pack
AI Pack
Dev Pack
Obsidian Pack
Bookmarks Pack
```

This keeps the app clean while allowing more specialized workflows.

## Personal scripts

Personal scripts are where user-specific workflows live.

Examples:

```txt
Rewrite in IRZ style
Draft Studio Pixel client reply
Extract tattoo brief
Save podcast research source
Create article source note
Generate tattoo prompt
Append to my Obsidian vault
```

These should not necessarily ship as default actions. They can exist as a private pack or imported YAML scripts.

## Input kinds

Winegold currently turns non-file drag payloads into temporary files:

```txt
selected text -> dragged-text.txt
URL -> dragged-url.url
HTML -> dragged-html.html
```

That works, but the app should also expose a higher-level detected kind.

Possible kinds:

```txt
file
folder
image
web-image
url
text
html
code
```

The UI could show:

```txt
Detected: URL
Detected: Text
Detected: Web image
Detected: HTML element
Detected: Local image file
```

Actions could match by extension, but also by kind.

Example YAML idea:

```yml
name: Save URL as bookmark
trigger:
  kind:
    - url
cmd:
  exec: 'bookmark-save "{{inside}}"'
```

## Text actions

Selected text is not always just text.

It can be:

```txt
a prompt to send to ChatGPT
a quote to save
a task to extract
a note to append
a message to reply to
a code snippet to explain
a bug report to clean up
```

Useful generic actions:

```txt
Ask ChatGPT
Summarize
Explain simply
Translate FR/EN
Translate EN/FR
Rewrite shorter
Rewrite cleaner
Improve prompt
Debug this
Make checklist
Extract action items
```

The simplest version opens:

```txt
https://chatgpt.com/?prompt=...
```

with the selected text injected into a preset prompt.

## Text to Obsidian

This could be an optional Obsidian pack.

Actions:

```txt
Add to Inbox
Append to Daily Note
Create atomic note
Create todo
Save quote
Save idea
Save article draft fragment
Save podcast research note
```

Example quick capture:

```md
# Capture - 2026-07-08 14:55

<selected text>

Source:
Tags: #inbox
```

Example atomic note:

```md
# Short generated title

## Summary

## Why it matters

## Notes

## Source
```

## Text for Studio Pixel / personal workflows

Personal actions can be much more specific.

Examples:

```txt
Extract tattoo brief
Draft client reply
Estimate tattoo request
Rewrite in IRZ style
Turn into Instagram caption
Create SEO title and meta description
Save as Studio Pixel article source
```

This belongs in a private pack, not in the built-in core.

## URL actions

A dragged URL can be a bookmark, an article, a source, a page to inspect, a video, a GitHub issue, or a direct asset.

## Bookmark actions

Basic actions:

```txt
Add bookmark
Add to read later
Copy markdown link
Save URL to project links
```

Example output:

```md
- [Page title](https://example.com) - 2026-07-08
```

## Smart bookmark

A richer bookmark action could fetch metadata.

Data to extract:

```txt
title
description
site name
favicon
canonical URL
Open Graph image
```

Example note:

```md
# Local-first software design

URL: https://example.com
Site: Example
Tags: #bookmark #dev #local-first
Status: unread

## Summary

Short generated summary.

## Why I saved it

Useful for thinking about Winegold as a local-first tool.
```

## Read later

Example:

```md
- [ ] [Article title](https://example.com)
```

Possible destinations:

```txt
Bookmarks/read-later.md
Obsidian daily note
Obsidian project note
```

## Project bookmarks

Useful for keeping sources per project.

Actions:

```txt
Bookmark to Winegold
Bookmark to Studio Pixel
Bookmark to IRZ
Bookmark to Dev refs
Bookmark to Tattoo refs
```

Possible output paths:

```txt
Vault/Projects/Winegold/links.md
Vault/Projects/Studio Pixel/links.md
Vault/References/Tattoo/links.md
```

## URL to markdown

Actions:

```txt
Save page as markdown
Extract readable article
Archive page text
Summarize page
```

Output:

```txt
Downloads/page-title.md
```

## SEO quick check

Useful for web projects.

Action:

```txt
URL -> SEO quick check
```

Extract:

```txt
status code
title
meta description
h1
canonical
og:title
og:description
og:image
robots
```

## Screenshot URL

Action:

```txt
URL -> full page screenshot
```

Possible implementation:

```txt
Playwright
Chrome headless
Browserless
```

Output:

```txt
screenshots/page-title.png
```

## Special URL types

GitHub URL:

```txt
Summarize issue
Summarize PR
Clone repo
Open in GitHub tooling
Create local note
```

YouTube URL:

```txt
Save to watch later
Extract transcript
Summarize video
Download thumbnail
Create podcast research note
```

Image URL:

```txt
Download image
Convert image
Save to moodboard
Extract palette
Create tattoo reference note
```

## Web image actions

Dragging an image from a browser is ambiguous.

The pasteboard can contain:

```txt
direct image URL
page URL
HTML with image source
local temporary file
PNG/TIFF image data
```

Winegold should detect web images in this order:

```txt
1. local file URL
2. direct image URL
3. HTML image source
4. image data from pasteboard
5. fallback to text/URL/HTML
```

Then expose:

```txt
Detected: Web image URL
Detected: Image data
Detected: HTML image
Detected: Local image file
```

Possible actions:

```txt
Download web image
Save image to Downloads
Save image to moodboard
Convert to WebP
Resize image
Extract palette
Copy image URL
Extract alt text
Create tattoo reference prompt
Reverse image search URL
```

## HTML / web element actions

Dragging a selected web block or HTML snippet can become a local web clipper.

Actions:

```txt
HTML to Markdown
Clean HTML
Extract readable text
Extract all links
Extract all images
Save selection to Obsidian
```

Example web clip output:

```md
# Web clip

Source:
Date: 2026-07-08

<cleaned content>
```

## Dev-focused HTML actions

Useful for frontend work.

```txt
Explain this component
Convert HTML to Tailwind
Convert HTML to Astro component
Convert HTML to React component
Extract CSS classes
Simplify markup
Check accessibility
```

## SEO-focused HTML actions

```txt
Extract headings
Check heading hierarchy
Extract links
Find images without alt text
Extract schema.org data
```

## Intent router

Instead of showing every action all the time, Winegold should route actions by detected input kind.

Example for text:

```txt
Detected: Text
Actions:
- Ask ChatGPT
- Summarize
- Save to Obsidian
- Make todo
- Clean text
```

Example for URL:

```txt
Detected: URL
Actions:
- Bookmark
- Read later
- Summarize page
- Save as markdown
- Screenshot
- SEO quick check
```

Example for web image:

```txt
Detected: Web image
Actions:
- Download
- Convert
- Save to moodboard
- Extract palette
```

## Suggested first action packs

### Web Pack

```txt
Open URL
Copy markdown link
Add bookmark
Add to read later
Save page as markdown
Summarize page
SEO quick check
Screenshot URL
```

### Text Pack

```txt
Ask ChatGPT
Summarize
Translate
Clean text
Make checklist
Extract todos
```

### Obsidian Pack

```txt
Add to Inbox
Append to Daily Note
Create atomic note
Create todo
Save quote
Save bookmark
```

### Image Pack

```txt
Download web image
Convert image
Resize image
Extract palette
Save to moodboard
```

### Dev Pack

```txt
Explain code
Create GitHub issue note
HTML to component
SEO quick check
```

## Top 5 to implement first

```txt
1. URL -> Markdown bookmark
2. URL -> SEO quick check
3. Text -> Ask ChatGPT with preset prompt
4. Text -> Save to Obsidian inbox
5. Web image -> Download / save to moodboard
```

## Product sentence

Winegold can become a local drag assistant:

```txt
file / text / url / html / image
-> local action
-> note
-> prompt
-> bookmark
-> automation
-> processed file
```

That is more interesting than just running scripts on files.
