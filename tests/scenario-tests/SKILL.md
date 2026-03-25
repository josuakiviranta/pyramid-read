---
name: pyramid-read
description: Read markdown files at configurable zoom levels. Use every time when you or subagents needs to read or gather information from  markdown files instead of "Read"-tool. Supports progressive disclosure — list headers first, expand only what's relevant.
allowed-tools: Bash
---

# Pyramid Reading with pyramid-read

Use `pyramid-read` via Bash instead of the `Read` tool for any markdown file.
This keeps context usage low. Load only what's relevant.

**Requires Bash access.** If you don't have it, respond with `NEEDS_CONTEXT: requires Bash permission to run pyramid-read`

## Quick start

```bash
pyramid-read docs/spec.md               # list all headers
pyramid-read docs/spec.md "## Overview" # read a specific section in full
pyramid-read docs/                      # survey folder — all .md files (headers ≤ depth 2) + all subfolders recursively
```
Workflow: survey/list → read. Load only what's relevant.

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
# →
# → docs/guides/
# → docs/guides/advanced/
# → docs/reference/

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
- Folder mode also lists all subdirectories recursively (with trailing slash) after the file blocks, sorted depth-first
