import os
import sys
from pyramid_read.parser import list_headers, extract_section


def _check_markdown(file_path: str) -> None:
    if not file_path.endswith(".md"):
        print(f"Error: not a markdown file: {file_path}", file=sys.stderr)
        sys.exit(1)


def _list_file(file_path: str) -> None:
    _check_markdown(file_path)
    try:
        with open(file_path) as f:
            text = f.read()
    except FileNotFoundError:
        print(f"Error: file not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    results = list_headers(text)
    print("\n".join(results))


def _expand_file(file_path: str, query: str) -> None:
    _check_markdown(file_path)
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
        all_entries = os.listdir(folder_path)
    except NotADirectoryError:
        print(f"Error: not a directory: {folder_path}", file=sys.stderr)
        sys.exit(1)

    md_files = sorted(e for e in all_entries if e.endswith(".md"))
    blocks = []
    for entry in md_files:
        file_path = os.path.join(folder_path, entry)
        with open(file_path) as f:
            text = f.read()
        headers = list_headers(text, max_depth=2)
        block = file_path + "\n\n" + "\n".join(headers)
        blocks.append(block)

    all_subdirs = []
    for dirpath, dirnames, _ in os.walk(folder_path):
        dirnames.sort()
        if dirpath != folder_path:
            all_subdirs.append(dirpath + "/")
    blocks.extend(all_subdirs)

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
