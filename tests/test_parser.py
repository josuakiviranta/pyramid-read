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
