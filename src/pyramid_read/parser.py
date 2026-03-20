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
