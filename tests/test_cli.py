import os
import subprocess
import tempfile
import pytest

SAMPLE_SPEC = os.path.join(os.path.dirname(__file__), "fixtures", "sample-spec.md")


def run(*args):
    result = subprocess.run(
        ["pyramid-read", *args],
        capture_output=True,
        text=True,
    )
    return result


class TestCLIListMode:
    def test_no_query_lists_all_headers(self):
        r = run(SAMPLE_SPEC)
        assert r.returncode == 0
        lines = r.stdout.strip().splitlines()
        assert lines[0] == "# Sample Spec"
        assert "## Summary" in lines
        assert "### Users" in lines

    def test_wrong_arg_count_exits_1(self):
        r = run(SAMPLE_SPEC, "##", "extra")
        assert r.returncode == 1
        assert "Usage:" in r.stderr


class TestCLIExpandMode:
    def test_expand_section_returns_content(self):
        r = run(SAMPLE_SPEC, "## Access")
        assert r.returncode == 0
        assert "### Users" in r.stdout
        assert "### Managers" in r.stdout
        assert "## Alerts" not in r.stdout

    def test_section_not_found_exits_1(self):
        r = run(SAMPLE_SPEC, "## Nonexistent")
        assert r.returncode == 1
        assert "section not found" in r.stderr


class TestCLIErrors:
    def test_missing_args_exits_1(self):
        r = run()
        assert r.returncode == 1
        assert "Usage:" in r.stderr

    def test_file_not_found_exits_1(self):
        r = run("nonexistent.md", "#")
        assert r.returncode == 1
        assert "file not found" in r.stderr

    def test_non_markdown_file_exits_1(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            f.write(b"# Not markdown\n")
            path = f.name
        r = run(path)
        assert r.returncode == 1
        assert "not a markdown file" in r.stderr

    def test_non_markdown_file_expand_exits_1(self):
        with tempfile.NamedTemporaryFile(suffix=".rst", delete=False) as f:
            f.write(b"Some content\n")
            path = f.name
        r = run(path, "## Section")
        assert r.returncode == 1
        assert "not a markdown file" in r.stderr


class TestCLIFolderMode:
    def setup_method(self):
        self.tmpdir = tempfile.mkdtemp()
        path_a = os.path.join(self.tmpdir, "a.md")
        path_b = os.path.join(self.tmpdir, "b.md")
        with open(path_a, "w") as f:
            f.write("# Alpha\n\n## Section A\n\n### Deep\n\nContent.\n")
        with open(path_b, "w") as f:
            f.write("# Beta\n\n## Section B\n\nContent.\n")
        self.path_a = path_a
        self.path_b = path_b

    def test_folder_lists_each_file(self):
        r = run(self.tmpdir)
        assert r.returncode == 0
        assert "a.md" in r.stdout
        assert "b.md" in r.stdout

    def test_folder_shows_headers_up_to_depth_2(self):
        r = run(self.tmpdir)
        assert "# Alpha" in r.stdout
        assert "## Section A" in r.stdout
        assert "### Deep" not in r.stdout

    def test_folder_files_separated_by_blank_lines(self):
        r = run(self.tmpdir)
        assert "\n\n" in r.stdout

    def test_folder_files_in_alphabetical_order(self):
        r = run(self.tmpdir)
        idx_a = r.stdout.index("a.md")
        idx_b = r.stdout.index("b.md")
        assert idx_a < idx_b

    def test_folder_ignores_non_md_files(self):
        txt_file = os.path.join(self.tmpdir, "notes.txt")
        with open(txt_file, "w") as f:
            f.write("# This should not appear\n")
        r = run(self.tmpdir)
        assert "notes.txt" not in r.stdout

    def test_folder_lists_subfolders_with_trailing_slash(self):
        subdir = os.path.join(self.tmpdir, "subsection")
        os.makedirs(subdir)
        r = run(self.tmpdir)
        assert r.returncode == 0
        assert "subsection/" in r.stdout

    def test_folder_subfolders_appear_after_files(self):
        subdir = os.path.join(self.tmpdir, "subsection")
        os.makedirs(subdir)
        r = run(self.tmpdir)
        idx_file = r.stdout.index("a.md")
        idx_dir = r.stdout.index("subsection/")
        assert idx_file < idx_dir

    def test_folder_subfolders_sorted_alphabetically(self):
        os.makedirs(os.path.join(self.tmpdir, "zzz"))
        os.makedirs(os.path.join(self.tmpdir, "aaa"))
        r = run(self.tmpdir)
        idx_aaa = r.stdout.index("aaa/")
        idx_zzz = r.stdout.index("zzz/")
        assert idx_aaa < idx_zzz

    def test_folder_with_only_subfolders_shows_them(self):
        empty_dir = tempfile.mkdtemp()
        os.makedirs(os.path.join(empty_dir, "child"))
        r = run(empty_dir)
        assert r.returncode == 0
        assert "child/" in r.stdout

    def test_folder_lists_nested_subfolders_recursively(self):
        os.makedirs(os.path.join(self.tmpdir, "parent", "child"))
        r = run(self.tmpdir)
        assert r.returncode == 0
        assert "parent/" in r.stdout
        assert "parent/child/" in r.stdout
