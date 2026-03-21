---
name: pyramid-read
description: Read markdown files at configurable zoom levels. Use when an agent needs
  to survey document structure without loading full content, or expand a specific section.
  Supports progressive disclosure — list headers first, expand only what's relevant.
allowed-tools: Bash(pyramid-read:*)
---

# Pyramid Reading with pyramid-read

## Quick start

```bash
pyramid-read docs/spec.md "#"               # survey top-level structure
pyramid-read docs/spec.md "##"              # expand one level deeper
pyramid-read docs/spec.md "## Overview"     # read a specific section in full
```

## Core workflow

1. **Survey** — list headers at level `#` to see the document shape
2. **Narrow** — list at `##` or `###` to find the relevant section
3. **Read** — expand the section you need by passing its full heading string

This keeps context usage low. Load only what's relevant.

## Commands

### List mode — query is only `#` characters

```bash
pyramid-read <file> "#"     # all level-1 headers
pyramid-read <file> "##"    # level-1 and level-2 headers
pyramid-read <file> "###"   # headers up to level 3
```

Output: one header per line, as they appear in the document.

### Expand mode — query is a full heading string

```bash
pyramid-read <file> "# Title"
pyramid-read <file> "## Section Name"
pyramid-read <file> "### Subsection"
```

Output: the heading line plus all content beneath it, including all subsections, until the next heading of equal or lesser depth.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | File not found, section not found, or wrong number of arguments |

Errors go to stderr. Output goes to stdout.

## Example: progressive document reading

```bash
# Step 1: what's in this document?
pyramid-read spec.md "#"
# → # Balancer Server Spec

# Step 2: what sections exist?
pyramid-read spec.md "##"
# → # Balancer Server Spec
# → ## Overview
# → ## Tech Stack
# → ## Authentication
# → ## Request Lifecycle

# Step 3: read the relevant section
pyramid-read spec.md "## Authentication"
# → ## Authentication
# →
# → ### Sellers
# → - Register via Firebase...
# →
# → ### Companies (Buyers)
# → ...
```

## Example: error handling

```bash
pyramid-read spec.md "## Nonexistent"
# stderr: Error: section not found: "## Nonexistent"
# exit code: 1

pyramid-read missing.md "#"
# stderr: Error: file not found: missing.md
# exit code: 1
```

## Notes

- Headings inside code fences (` ``` `) are ignored — they are not treated as document structure
- Expand mode is deep: it captures the heading plus all nested subsections
- List mode at level N includes all headers from level 1 through N
