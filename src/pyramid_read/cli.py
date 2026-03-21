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
