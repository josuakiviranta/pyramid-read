import os
import subprocess
import pytest

BALANCER_SERVER = os.path.join(os.path.dirname(__file__), "fixtures", "balancer-server.md")


def run(*args):
    result = subprocess.run(
        ["pyramid-read", *args],
        capture_output=True,
        text=True,
    )
    return result


class TestCLIListMode:
    def test_no_query_lists_all_headers(self):
        r = run(BALANCER_SERVER)
        assert r.returncode == 0
        lines = r.stdout.strip().splitlines()
        assert lines[0] == "# Balancer Server Spec"
        assert "## Overview" in lines
        assert "### Sellers" in lines

    def test_wrong_arg_count_exits_1(self):
        r = run(BALANCER_SERVER, "##", "extra")
        assert r.returncode == 1
        assert "Usage:" in r.stderr


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
        r = run()
        assert r.returncode == 1
        assert "Usage:" in r.stderr

    def test_file_not_found_exits_1(self):
        r = run("nonexistent.md", "#")
        assert r.returncode == 1
        assert "file not found" in r.stderr
