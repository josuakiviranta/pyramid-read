import os
import sys
from pyramid_read.parser import list_headers, extract_section


def _list_file(file_path: str) -> None:
    try:
        with open(file_path) as f:
            text = f.read()
    except FileNotFoundError:
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    results = list_headers(text)
    print("\n".join(results))


def _expand_file(file_path: str, query: str) -> None:
    try:
        with open(file_path) as f:
            text = f.read()
    except FileNotFoundError:
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    try:
        print(extract_section(text, query))
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def _folder_mode(folder_path: str) -> None:
    try:
        entries = sorted(
            e for e in os.listdir(folder_path) if e.endswith(".md")
        )
    except NotADirectoryError:
        print(f"Error: not a directory: {folder_path}", file=sys.stderr)
        sys.exit(1)

    blocks = []
    for entry in entries:
        file_path = os.path.join(folder_path, entry)
        with open(file_path) as f:
            text = f.read()
        headers = list_headers(text, max_depth=2)
        block = file_path + "\n\n" + "\n".join(headers)
        blocks.append(block)

    print("\n\n".join(blocks))


def main():
    args = sys.argv[1:]

    if len(args) == 1:
        path = args[0]
        if os.path.isdir(path):
            _folder_mode(path)
        else:
            _list_file(path)
    elif len(args) == 2:
        _expand_file(args[0], args[1])
    else:
        print("Usage: pyramid-read <file>", file=sys.stderr)
        print("       pyramid-read <file> <query>", file=sys.stderr)
        print("       pyramid-read <folder>", file=sys.stderr)
        sys.exit(1)
