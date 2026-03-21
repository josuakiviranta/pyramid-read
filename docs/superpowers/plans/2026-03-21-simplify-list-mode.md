# Simplify List Mode Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace depth-based list commands (`#`, `##`, `###`) with a single `#` command that lists all headers at all depths.

**Architecture:** Remove `max_level` from `list_headers`, change CLI to treat any `#+` query as "list all headers", update tests and docs to match. No new files — only modifications to existing files.

**Tech Stack:** Python 3.8+, pytest

---

## Chunk 1: Update parser

### Task 1: Update parser tests for new `list_headers` signature

**Files:**
- Modify: `tests/test_parser.py`

- [ ] **Step 1: Replace depth-specific tests with "lists all headers" tests**

In `tests/test_parser.py`, replace the `TestListHeaders` class with:

```python
class TestListHeaders:
    def test_returns_all_headers(self):
        text = read(BALANCER_SERVER)
        result = list_headers(text)
        assert result[0] == "# Balancer Server Spec"
        assert "## Overview" in result
        assert "## Authentication" in result
        assert "### Sellers" in result

    def test_hashes_in_code_fence_are_ignored(self):
        text = "# Real Header\n```\n# not a header\n```\n## Also Real\n"
        result = list_headers(text)
        assert result == ["# Real Header", "## Also Real"]

    def test_empty_document(self):
        assert list_headers("") == []

    def test_returns_headers_of_all_depths(self):
        text = "# H1\n## H2\n### H3\n#### H4\n"
        result = list_headers(text)
        assert result == ["# H1", "## H2", "### H3", "#### H4"]
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/josu/Documents/projects/pyramid-read && pytest tests/test_parser.py::TestListHeaders -v
```

Expected: FAIL — `list_headers()` still requires `max_level` argument.

---

### Task 2: Update `list_headers` in parser

**Files:**
- Modify: `src/pyramid_read/parser.py:14`

- [ ] **Step 3: Remove `max_level` parameter from `list_headers`**

Change:
```python
def list_headers(text: str, max_level: int) -> list:
    return [line for level, line in _iter_headings(text) if level <= max_level]
```

To:
```python
def list_headers(text: str) -> list:
    return [line for _, line in _iter_headings(text)]
```

- [ ] **Step 4: Run parser tests to verify they pass**

```bash
cd /Users/josu/Documents/projects/pyramid-read && pytest tests/test_parser.py -v
```

Expected: All `TestListHeaders` tests PASS. `TestExtractSection` tests PASS (unchanged).

- [ ] **Step 5: Commit**

```bash
cd /Users/josu/Documents/projects/pyramid-read && git add src/pyramid_read/parser.py tests/test_parser.py && git commit -m "refactor: list_headers returns all headers, remove max_level param"
```

---

## Chunk 2: Update CLI

### Task 3: Update CLI tests for simplified list mode

**Files:**
- Modify: `tests/test_cli.py`

- [ ] **Step 6: Replace depth-specific CLI list tests with single-command test**

In `tests/test_cli.py`, replace `TestCLIListMode` with:

```python
class TestCLIListMode:
    def test_hash_lists_all_headers(self):
        r = run(BALANCER_SERVER, "#")
        assert r.returncode == 0
        lines = r.stdout.strip().splitlines()
        assert lines[0] == "# Balancer Server Spec"
        assert "## Overview" in lines
        assert "### Sellers" in lines
```

- [ ] **Step 7: Run CLI tests to verify the new test fails**

```bash
cd /Users/josu/Documents/projects/pyramid-read && pytest tests/test_cli.py::TestCLIListMode -v
```

Expected: FAIL — `list_headers` call in `cli.py` still passes `len(query)` as argument.

---

### Task 4: Update CLI to call `list_headers` without depth

**Files:**
- Modify: `src/pyramid_read/cli.py`

- [ ] **Step 8: Remove depth argument from `list_headers` call in CLI**

Change:
```python
if _LEVEL_RE.match(query):
    results = list_headers(text, len(query))
    print("\n".join(results))
```

To:
```python
if _LEVEL_RE.match(query):
    results = list_headers(text)
    print("\n".join(results))
```

- [ ] **Step 9: Run all tests to verify everything passes**

```bash
cd /Users/josu/Documents/projects/pyramid-read && pytest -v
```

Expected: All tests PASS.

- [ ] **Step 10: Commit**

```bash
cd /Users/josu/Documents/projects/pyramid-read && git add src/pyramid_read/cli.py tests/test_cli.py && git commit -m "feat: simplify list mode — '#' lists all headers at all depths"
```

---

## Chunk 3: Update docs

### Task 5: Update README and SKILL.md

**Files:**
- Modify: `README.md`
- Modify: `SKILL.md`

- [ ] **Step 11: Update README list-headers section**

In `README.md`, replace:

```markdown
**List headers by depth:**

```bash
pyramid-read file.md "#"    # all top-level headers
pyramid-read file.md "##"   # top-level and second-level headers
pyramid-read file.md "###"  # headers up to depth 3
```
```

With:

```markdown
**List all headers:**

```bash
pyramid-read file.md "#"    # all headers at every depth
```
```

Also update the Example section — replace:

```
$ pyramid-read docs/spec.md "#"
# Document name

$ pyramid-read docs/spec.md "##"
# Document name
## Overview
## Tech Stack
## Authentication
## Request Lifecycle
```

With:

```
$ pyramid-read docs/spec.md "#"
# Document name
## Overview
## Tech Stack
## Authentication
### Users
### Admins
## Request Lifecycle
```

- [ ] **Step 12: Update SKILL.md commands section**

In `SKILL.md`, replace the `### List mode — query is only '#' characters` block:

```markdown
### List mode — query is only `#` characters

```bash
pyramid-read <file> "#"     # all level-1 headers
pyramid-read <file> "##"    # level-1 and level-2 headers
pyramid-read <file> "###"   # headers up to level 3
```

Output: one header per line, as they appear in the document.
```

With:

```markdown
### List mode — `"#"` lists all headers

```bash
pyramid-read <file> "#"     # all headers at every depth
```

Output: one header per line, as they appear in the document.
```

Also update the Quick start block and the subagent section to remove `"##"` command, and update the progressive reading example in the file — Step 2 should use `"#"` (not `"##"`) since `"#"` now shows all levels.

- [ ] **Step 13: Commit**

```bash
cd /Users/josu/Documents/projects/pyramid-read && git add README.md SKILL.md && git commit -m "docs: update README and SKILL.md for simplified list mode"
```
