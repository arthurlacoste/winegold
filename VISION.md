# Winegold Vision

Winegold should make small local automations feel as simple as using a native Mac app.

The core idea is:

```text
Give Winegold something.
Choose what should happen.
Get the result immediately.
```

A file, folder, URL, selected text, or no input at all can become the starting point for one useful action.

Winegold is not intended to become a large visual programming environment or a replacement for the terminal. It should remain a lightweight layer between everyday inputs and small developer tools.

## Who it is for

Winegold is primarily for people who repeatedly perform small technical tasks:

- developers
- designers and creative technologists
- power users
- people maintaining their own scripts
- people who want local automation without building a complete app

The user should not need to remember a command, open the correct terminal directory, or maintain a custom launcher for every task.

## The product promise

Winegold turns scripts into visible, searchable, reusable tools.

A recipe should feel closer to a tiny native utility than to a shell snippet hidden in a folder.

Winegold should provide:

- a global searchable palette
- drag-and-drop discovery based on the input
- clear input requirements
- safe local execution
- understandable progress and errors
- simple installation and sharing of recipes

## Small tools, composed naturally

Most useful automations are not large applications. They are small tools:

- resize an image
- inspect a project
- run tests
- create a Markdown note
- transform selected text
- convert a file
- open a project in the right application
- copy or extract useful information

Winegold should make these tools easy to launch individually, but also allow them to work together.

A recipe may expose several related actions:

```text
Project tools
├── Open in editor
├── Start development server
├── Run tests
├── Open local website
└── Copy project summary
```

This avoids filling the interface with hundreds of disconnected recipes while keeping every action explicit.

## Multiple tools at the same time

A future Winegold workflow may launch several small tools together when they form one understandable operation.

Example:

```text
Start working on this project
├── open the folder in the editor
├── start the development server
├── open the local URL in the browser
└── open the project task list
```

The goal is not unrestricted orchestration by default. The user should always understand what will launch.

Useful principles:

- every launched action remains visible
- parallel actions are shown as separate tasks
- failure of one tool does not hide the others
- actions can be cancelled independently where possible
- Winegold shows which process or application was opened
- recipes must declare external dependencies clearly

## Winegold and other applications

Winegold does not need to reproduce the interface of every tool it launches.

It can act as a local coordination layer and hand work to the best application:

- Finder for files and folders
- Terminal for an interactive command
- a code editor for a project
- a browser for a local server or URL
- Preview or an image editor for generated assets
- Obsidian or another notes app for captured text
- another local automation app when that integration is useful

The important part is that Winegold owns the entry point, the recipe, and the explanation of what happened.

Winegold should prefer native macOS mechanisms such as `open`, URLs, files, and application identifiers rather than deep custom integrations when a simple handoff is enough.

## Developer workflows

Winegold should be especially useful for repetitive development work.

Examples:

### Inspect a project

```text
Drop a repository
→ detect its type
→ show relevant actions
```

Possible actions:

- show Git status
- identify package manager
- list available scripts
- count source files
- inspect dependencies
- open README
- run the correct test command

### Start a work session

```text
Choose a project
→ launch the tools needed for that project
```

Possible results:

- editor opened
- development server running
- browser opened
- logs visible
- task tracker opened

### Run several checks

```text
Run project checks
├── formatting
├── linting
├── tests
└── build
```

These checks may run in parallel when independent. Winegold should show their states together instead of hiding them behind one opaque command.

## Recipes as the product surface

Recipes are not only configuration files. They are Winegold's extension model and primary product surface.

A good recipe should be:

- readable
- portable
- reviewable
- deterministic where possible
- explicit about input and dependencies
- safe to inspect before installation
- easy to edit without learning a framework

The YAML format should remain small enough to write manually while allowing richer behavior through focused additions.

Winegold should avoid turning recipes into a general-purpose programming language. Complex logic belongs in an external script referenced by the recipe.

## Progressive complexity

Winegold should work at three levels.

### 1. Immediate utilities

Built-in or starter recipes that work without configuration.

Examples:

- copy path
- reveal in Finder
- convert image
- resize image
- save selected text

### 2. Installed tool packs

Curated groups for common domains.

Examples:

- developer tools
- image tools
- text tools
- web tools
- AI tools
- Obsidian tools

### 3. Personal workflows

Recipes specific to one person, project, or organization.

Examples:

- start one particular project environment
- prepare a release
- create a project-specific note
- invoke a local model with a custom prompt
- open a known set of applications and resources

Winegold should make all three levels feel coherent without forcing personal workflows into the public catalogue.

## What Winegold should not become

Winegold should not become:

- a full IDE
- a terminal emulator
- a general workflow canvas
- a background automation daemon with invisible behavior
- a replacement for Alfred, Raycast, Shortcuts, Automator, or shell scripting
- a cloud automation platform
- an agent that changes the system without explicit user intent

Winegold may interoperate with these tools, import some workflows, or launch them, but its own identity remains focused:

```text
small local tools, made visible and easy to run
```

## Product principles

### Local first

Recipes and commands run locally. User scripts remain under user control.

### Instant shell

The interface appears immediately. Slow recipes or filesystem operations never block the first frame.

### Visible execution

The user can see what is running, what completed, and what failed.

### Explicit composition

Launching multiple tools is allowed, but never hidden or surprising.

### Small core, extensible edges

The native app stays focused. Recipes provide specialization.

### Native handoff over reinvention

When another application already provides the correct interface, Winegold opens or feeds that application instead of rebuilding it.

### Useful before powerful

The first successful action should take minutes, not hours of configuration.

## Near-term direction

Before and during beta, focus on:

- onboarding
- a reliable starter recipe pack
- clear versioning and releases
- stable palette and drag workflows
- useful diagnostics
- understandable multi-file progress
- feedback from a small group of real users

## Later direction

After the beta foundation is stable, explore:

- parallel multi-tool workflows
- richer task status and cancellation
- project-aware developer packs
- a curated recipe catalogue
- safe import of simple Alfred workflows
- update management
- recipe provenance and trust
- lightweight handoffs to local agents and AI tools

These additions should strengthen the original idea rather than turn Winegold into a broad automation platform.

## The simplest expression of the vision

```text
Winegold gives small scripts the usability of small apps.
```

For a developer, that can mean dropping a project and launching the few tools needed to work on it.

For another user, it can mean transforming a file, URL, or piece of text in one step.

The common experience is simple: the right little tools are visible, understandable, and ready when needed.
