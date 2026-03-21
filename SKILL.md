---
name: pyramid-read
description: Read markdown files at configurable zoom levels. Use every time when agent or subagents needs to read markdown files instead of "Read"-tool. Supports progressive disclosure — list headers first, expand only what's relevant.
allowed-tools: Bash(pyramid-read:*)
---

# Pyramid Reading with pyramid-read

## If you are a subagent

Use `pyramid-read` via Bash instead of the `Read` tool for any markdown file.

**Requires Bash access.** If you don't have it, respond with `NEEDS_CONTEXT: requires Bash permission to run pyramid-read`

```bash
pyramid-read <file.md>                   # list all headers
pyramid-read <file.md> "## Section Name" # read a full section
pyramid-read <folder>                    # survey folder (headers ≤ depth 2 per file)
```

Workflow: survey/list → read. Load only what's relevant.

## If you are dispatching subagents

Use `subagent_type: "pyramid-reader"` — a custom subagent with `Bash(pyramid-read:*)` pre-authorized in its `tools` field.

**Why:** Claude Code's permission system auto-denies Bash in subagents unless it is listed in the subagent's `tools` frontmatter. A prompt-time grant is not enough.

The `pyramid-reader` subagent is defined in `.claude/agents/pyramid-reader.md`. Copy it to `~/.claude/agents/` to make it available across all projects.

## Quick start

```bash
pyramid-read docs/spec.md               # list all headers
pyramid-read docs/spec.md "## Overview" # read a specific section in full
pyramid-read docs/                      # survey folder — all .md files, headers ≤ depth 2
```

## Core workflow

1. **Survey** — run `pyramid-read <folder>` to see headers across all docs in a folder (depth ≤ 2)
2. **List** — run `pyramid-read <file>` to see all headers in one file
3. **Read** — expand the section you need by passing its full heading string

This keeps context usage low. Load only what's relevant.

## Commands

### List mode — no query argument

```bash
pyramid-read <file>     # all headers at every depth
```

Output: one header per line, as they appear in the document.

### Expand mode — query is a full heading string

```bash
pyramid-read <file> "# Title"
pyramid-read <file> "## Section Name"
pyramid-read <file> "### Subsection"
```

Output: the heading line plus all content beneath it, including all subsections, until the next heading of equal or lesser depth.

### Folder mode — path is a directory

```bash
pyramid-read <folder>   # each .md file with headers at depth ≤ 2
```

Output: for each .md file (alphabetical), the file path followed by its depth-1 and depth-2 headers. File blocks separated by blank lines.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | File not found, section not found, or wrong number of arguments |

Errors go to stderr. Output goes to stdout.

## Example: progressive document reading

```bash
# Step 1: survey the docs folder
pyramid-read docs/
# → docs/spec.md
# →
# → # Backend Server Spec
# → ## Overview
# → ## Authentication
# → ## Request Lifecycle

# Step 2: list all headers in a specific file
pyramid-read docs/spec.md
# → # Backend Server Spec
# → ## Overview
# → ## Authentication
# → ### Sellers
# → ## Request Lifecycle

# Step 3: read the relevant section
pyramid-read docs/spec.md "## Authentication"
# → ## Authentication
# →
# → ### Sellers
# → - Register via Firebase...
```

## Example: error handling

```bash
pyramid-read spec.md "## Nonexistent"
# stderr: Error: section not found: "## Nonexistent"
# exit code: 1

pyramid-read missing.md
# stderr: Error: file not found: missing.md
# exit code: 1
```

## Notes

- Headings inside code fences (` ``` `) are ignored — they are not treated as document structure
- Expand mode is deep: it captures the heading plus all nested subsections
- List mode returns all headers at every depth
- Folder mode returns headers at depth ≤ 2 only (h1 and h2)
