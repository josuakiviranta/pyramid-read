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
