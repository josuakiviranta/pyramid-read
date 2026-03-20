# pyramid-read Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Python CLI tool that reads markdown files at configurable zoom levels — list headers by depth or expand a named section fully.

**Architecture:** Two modules: `parser.py` (pure functions, no I/O) and `cli.py` (entry point, file reading, stdout output). Installed as a global `pyramid-read` command via `pyproject.toml`. Tests in `tests/test_parser.py` use real example files from `examples/specs/`.

**Tech Stack:** Python 3.8+, stdlib only, pytest for tests, pip-installable via pyproject.toml.

---

## Chunk 1: Project scaffold + parser core

### Task 1: Project scaffold

**Files:**
- Create: `pyproject.toml`
- Create: `src/pyramid_read/__init__.py`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p src/pyramid_read tests
```

- [ ] **Step 2: Create pyproject.toml**

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "pyramid-read"
version = "0.1.0"
requires-python = ">=3.8"

[project.scripts]
pyramid-read = "pyramid_read.cli:main"

[tool.setuptools.packages.find]
where = ["src"]
```

- [ ] **Step 3: Create empty `__init__.py`**

Create `src/pyramid_read/__init__.py` with empty content.

- [ ] **Step 4: Install in editable mode**

```bash
pip install -e .
```

Expected: installs without error, `pyramid-read` command becomes available.

- [ ] **Step 5: Commit**

```bash
git add pyproject.toml src/
git commit -m "chore: scaffold project with pyproject.toml"
```

---

### Task 2: `list_headers` — failing tests first

**Files:**
- Create: `tests/test_parser.py`
- Reference: `examples/specs/balancer-server.md`

The file `examples/specs/balancer-server.md` starts with `# Balancer Server Spec`, then has `## Overview`, `## Tech Stack`, `## Actors`, `## Request Lifecycle`, `## Authentication`, `## Notifications`, and more `##` sections. `## Authentication` contains `### Sellers`, `### Companies (Buyers)`, `### Admin`.

- [ ] **Step 1: Write failing tests for `list_headers`**

Create `tests/test_parser.py`:

```python
import os
import pytest
from pyramid_read.parser import list_headers, extract_section

EXAMPLES = os.path.join(os.path.dirname(__file__), "..", "examples", "specs")
BALANCER_SERVER = os.path.join(EXAMPLES, "balancer-server.md")


def read(path):
    with open(path) as f:
        return f.read()


class TestListHeaders:
    def test_level1_returns_only_h1(self):
        text = read(BALANCER_SERVER)
        result = list_headers(text, 1)
        assert result == ["# Balancer Server Spec"]

    def test_level2_includes_h1_and_h2(self):
        text = read(BALANCER_SERVER)
        result = list_headers(text, 2)
        assert result[0] == "# Balancer Server Spec"
        assert "## Overview" in result
        assert "## Tech Stack" in result
        assert "## Authentication" in result
        # no h3 at level 2
        assert not any(h.startswith("### ") for h in result)

    def test_level3_includes_h3(self):
        text = read(BALANCER_SERVER)
        result = list_headers(text, 3)
        assert "### Sellers" in result
        assert "### Companies (Buyers)" in result
        assert "### Admin" in result

    def test_hashes_in_code_fence_are_ignored(self):
        text = "# Real Header\n```\n# not a header\n```\n## Also Real\n"
        result = list_headers(text, 2)
        assert result == ["# Real Header", "## Also Real"]

    def test_empty_document(self):
        assert list_headers("", 2) == []

    def test_no_headers_at_requested_level(self):
        text = "# Only Top Level\n\nsome content\n"
        assert list_headers(text, 1) == ["# Only Top Level"]
        assert list_headers(text, 2) == ["# Only Top Level"]
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_parser.py -v
```

Expected: `ImportError` or `ModuleNotFoundError` — `parser` does not exist yet.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test_parser.py
git commit -m "test: add failing tests for list_headers"
```

---

### Task 3: Implement `list_headers`

**Files:**
- Create: `src/pyramid_read/parser.py`

- [ ] **Step 1: Implement `list_headers` in `parser.py`**

```python
import re

_HEADING_RE = re.compile(r'^(#{1,6})\s+\S')


def _is_fence(line: str) -> bool:
    return line.strip().startswith('```')


def _iter_headings(text: str):
    """Yield (level, raw_line) for each heading not inside a code fence."""
    in_fence = False
    for line in text.splitlines():
        if _is_fence(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = _HEADING_RE.match(line)
        if m:
            yield len(m.group(1)), line


def list_headers(text: str, max_level: int) -> list:
    return [line for level, line in _iter_headings(text) if level <= max_level]


def extract_section(text: str, heading: str) -> str:
    raise NotImplementedError
```

- [ ] **Step 2: Run `list_headers` tests**

```bash
pytest tests/test_parser.py::TestListHeaders -v
```

Expected: all 6 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add src/pyramid_read/parser.py
git commit -m "feat: implement list_headers with code fence awareness"
```

---

### Task 4: `extract_section` — failing tests first

**Files:**
- Modify: `tests/test_parser.py`

- [ ] **Step 1: Add failing tests for `extract_section`**

Append to `tests/test_parser.py`:

```python
class TestExtractSection:
    def test_returns_heading_and_content(self):
        text = "# Title\n\nIntro text.\n\n## Overview\n\nSome overview content.\n\n## Next\n\nOther.\n"
        result = extract_section(text, "## Overview")
        assert result.startswith("## Overview")
        assert "Some overview content." in result
        assert "## Next" not in result

    def test_includes_subsections(self):
        text = read(BALANCER_SERVER)
        result = extract_section(text, "## Authentication")
        assert "## Authentication" in result
        assert "### Sellers" in result
        assert "### Companies (Buyers)" in result
        assert "### Admin" in result

    def test_stops_at_sibling_heading(self):
        text = read(BALANCER_SERVER)
        result = extract_section(text, "## Authentication")
        assert "## Notifications" not in result

    def test_stops_at_parent_heading(self):
        text = "# Doc\n\n## Section\n\nContent.\n\n# NewDoc\n\nOther.\n"
        result = extract_section(text, "## Section")
        assert "# NewDoc" not in result

    def test_section_not_found_raises(self):
        text = read(BALANCER_SERVER)
        with pytest.raises(ValueError, match="section not found"):
            extract_section(text, "## Nonexistent Section")

    def test_h1_section_captures_all_children(self):
        text = "# Doc\n\nIntro.\n\n## A\n\nA content.\n\n## B\n\nB content.\n"
        result = extract_section(text, "# Doc")
        assert "## A" in result
        assert "## B" in result
```

- [ ] **Step 2: Run to confirm they fail**

```bash
pytest tests/test_parser.py::TestExtractSection -v
```

Expected: FAIL — `NotImplementedError`.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test_parser.py
git commit -m "test: add failing tests for extract_section"
```

---

### Task 5: Implement `extract_section`

**Files:**
- Modify: `src/pyramid_read/parser.py`

- [ ] **Step 1: Replace `NotImplementedError` stub with implementation**

Replace the `extract_section` function in `parser.py`:

```python
def extract_section(text: str, heading: str) -> str:
    heading = heading.rstrip()
    m = _HEADING_RE.match(heading)
    if not m:
        raise ValueError(f"section not found: \"{heading}\"")
    target_level = len(m.group(1))

    lines = text.splitlines(keepends=True)
    in_fence = False
    start = None

    for i, line in enumerate(lines):
        if _is_fence(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line.rstrip() == heading:
            start = i
            break

    if start is None:
        raise ValueError(f"section not found: \"{heading}\"")

    result = []
    in_fence = False
    for line in lines[start:]:
        if _is_fence(line):
            in_fence = not in_fence
            result.append(line)
            continue
        if in_fence:
            result.append(line)
            continue
        hm = _HEADING_RE.match(line)
        if hm and len(hm.group(1)) <= target_level and result:
            # reached a sibling or parent heading — stop
            break
        result.append(line)

    return "".join(result).rstrip("\n")
```

- [ ] **Step 2: Run all parser tests**

```bash
pytest tests/test_parser.py -v
```

Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add src/pyramid_read/parser.py
git commit -m "feat: implement extract_section with deep capture"
```

---

## Chunk 2: CLI + integration

### Task 6: `cli.py` — failing tests first

**Files:**
- Create: `tests/test_cli.py`

- [ ] **Step 1: Write failing CLI tests**

Create `tests/test_cli.py`:

```python
import os
import subprocess
import sys
import pytest

EXAMPLES = os.path.join(os.path.dirname(__file__), "..", "examples", "specs")
BALANCER_SERVER = os.path.join(EXAMPLES, "balancer-server.md")


def run(*args):
    result = subprocess.run(
        ["pyramid-read", *args],
        capture_output=True,
        text=True,
    )
    return result


class TestCLIListMode:
    def test_level1_returns_h1(self):
        r = run(BALANCER_SERVER, "#")
        assert r.returncode == 0
        assert r.stdout.strip() == "# Balancer Server Spec"

    def test_level2_returns_h1_and_h2(self):
        r = run(BALANCER_SERVER, "##")
        assert r.returncode == 0
        lines = r.stdout.strip().splitlines()
        assert lines[0] == "# Balancer Server Spec"
        assert "## Overview" in lines
        assert not any(l.startswith("### ") for l in lines)

    def test_level3_includes_h3(self):
        r = run(BALANCER_SERVER, "###")
        assert r.returncode == 0
        lines = r.stdout.strip().splitlines()
        assert "### Sellers" in lines


class TestCLIExpandMode:
    def test_expand_section_returns_content(self):
        r = run(BALANCER_SERVER, "## Authentication")
        assert r.returncode == 0
        assert "### Sellers" in r.stdout
        assert "### Admin" in r.stdout
        assert "## Notifications" not in r.stdout

    def test_section_not_found_exits_1(self):
        r = run(BALANCER_SERVER, "## Nonexistent")
        assert r.returncode == 1
        assert "section not found" in r.stderr


class TestCLIErrors:
    def test_missing_args_exits_1(self):
        r = run(BALANCER_SERVER)
        assert r.returncode == 1
        assert "Usage:" in r.stderr

    def test_file_not_found_exits_1(self):
        r = run("nonexistent.md", "#")
        assert r.returncode == 1
        assert "file not found" in r.stderr
```

- [ ] **Step 2: Run to confirm they fail**

```bash
pytest tests/test_cli.py -v
```

Expected: FAIL — `pyramid-read` command not yet implemented.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test_cli.py
git commit -m "test: add failing CLI integration tests"
```

---

### Task 7: Implement `cli.py`

**Files:**
- Create: `src/pyramid_read/cli.py`

- [ ] **Step 1: Create `cli.py`**

```python
import sys
import re
from pyramid_read.parser import list_headers, extract_section

_LEVEL_RE = re.compile(r'^#+$')


def main():
    if len(sys.argv) != 3:
        print("Usage: pyramid-read <file> <query>", file=sys.stderr)
        sys.exit(1)

    file_path, query = sys.argv[1], sys.argv[2]

    try:
        with open(file_path) as f:
            text = f.read()
    except FileNotFoundError:
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)

    if _LEVEL_RE.match(query):
        results = list_headers(text, len(query))
        print("\n".join(results))
    else:
        try:
            print(extract_section(text, query))
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
```

- [ ] **Step 2: Run all tests**

```bash
pytest tests/ -v
```

Expected: all tests PASS.

- [ ] **Step 3: Smoke test manually**

```bash
pyramid-read examples/specs/balancer-server.md "#"
pyramid-read examples/specs/balancer-server.md "##"
pyramid-read examples/specs/balancer-server.md "## Authentication"
```

Expected: clean output, no errors.

- [ ] **Step 4: Commit**

```bash
git add src/pyramid_read/cli.py
git commit -m "feat: implement CLI entry point with list and expand modes"
```

---

### Task 8: Final check

- [ ] **Step 1: Run full test suite**

```bash
pytest tests/ -v
```

Expected: all tests PASS, 0 failures.

- [ ] **Step 2: Verify install works cleanly from scratch**

```bash
pip install -e .
pyramid-read --help 2>&1 || pyramid-read examples/specs/balancer-server.md "#"
```

Expected: outputs `# Balancer Server Spec`.

- [ ] **Step 3: Final commit if any loose files**

```bash
git status
```

If clean, done. If not:

```bash
git add -A
git commit -m "chore: finalize pyramid-read v0.1.0"
```
