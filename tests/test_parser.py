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
