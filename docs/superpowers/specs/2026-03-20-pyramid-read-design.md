# pyramid-read Design

## Overview

`pyramid-read` is a Python CLI tool for reading markdown files in a pyramid (zoom-level) manner. Primary consumer is an AI agent that navigates documents progressively — surveying headers at a high level, then expanding specific sections only when needed. Inspired by multi-resolution image formats and map tiles: zoom out to survey, zoom in to read.

---

## Goals

- Let an AI agent enumerate document structure without loading full content
- Let an AI agent expand any section fully once identified as relevant
- Zero external dependencies (pure Python, stdlib only)
- Extensible to other file types (Python, JS) in future

---

## CLI Interface

Positional args: `pyramid-read <file> <query>`

**List mode** — query is only `#` characters:

```bash
pyramid-read file.md "#"    # all level-1 headers
pyramid-read file.md "##"   # all level-1 and level-2 headers
pyramid-read file.md "###"  # all headers up to level 3
```

Output: one header per line, as-is from the source (e.g. `## Overview`)

**Expand mode** — query is a full heading string:

```bash
pyramid-read file.md "## Authentication"   # full content of that section (deep)
pyramid-read file.md "# Balancer Server Spec"
```

Output: the heading line + all content beneath it until the next heading of equal or lesser depth. Includes all subsections.

---

## Architecture

```
src/
  pyramid_read/
    parser.py      # pure functions, no I/O
    cli.py         # entry point, file I/O, arg dispatch, stdout output
pyproject.toml     # installable as `pyramid-read` CLI command
tests/
  test_parser.py   # pytest, uses examples/ files
examples/          # real markdown files used as test fixtures
```

### parser.py

Two public functions:

- `list_headers(text: str, max_level: int) -> list[str]`
  Returns all heading lines where heading depth <= max_level, in document order.

- `extract_section(text: str, heading: str) -> str`
  Returns heading line + all content until next heading of equal or lesser depth. Deep: includes all subsections.

Both functions skip lines inside code fences (` ``` ` blocks) to avoid matching `#` inside code examples.

### cli.py

- Reads `sys.argv[1]` (file path) and `sys.argv[2]` (query)
- Detects mode: if query matches `/^#+$/` → list mode, else → expand mode
- Reads file, calls parser, prints result to stdout
- All errors go to stderr, exit code 1

---

## Error Handling

| Condition | Output | Exit |
|---|---|---|
| Wrong arg count | `Usage: pyramid-read <file> <query>` | 1 |
| File not found | `Error: file not found: <path>` | 1 |
| Section not found (expand) | `Error: section not found: "<heading>"` | 1 |
| No headers at level (list) | empty output | 0 |

---

## Testing

`tests/test_parser.py` using pytest against files in `examples/specs/`:

- `list_headers` at levels 1, 2, 3 returns correct headers
- `extract_section` returns content including all subsections
- `extract_section` stops at next sibling heading
- `#` inside code fences is not treated as a heading
- Section not found raises appropriate error

---

## Future Extension

The two-module split makes adding new file types straightforward:

- `parse_python(text)` — classes/functions as headers, method bodies as sections
- `parse_js(text)` — same for JS/TS
- `cli.py` routes to the right parser by file extension

Interface stays identical from caller's perspective.
