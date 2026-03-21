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
