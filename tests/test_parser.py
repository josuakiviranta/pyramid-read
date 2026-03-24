import os
import pytest
from pyramid_read.parser import list_headers, extract_section

SAMPLE_SPEC = os.path.join(os.path.dirname(__file__), "fixtures", "sample-spec.md")


def read(path):
    with open(path) as f:
        return f.read()


class TestListHeaders:
    def test_returns_all_headers(self):
        text = read(SAMPLE_SPEC)
        result = list_headers(text)
        assert result[0] == "# Sample Spec"
        assert "## Summary" in result
        assert "## Access" in result
        assert "### Users" in result

    def test_hashes_in_code_fence_are_ignored(self):
        text = "# Real Header\n```\n# not a header\n```\n## Also Real\n"
        result = list_headers(text)
        assert result == ["# Real Header", "## Also Real"]

    def test_empty_document(self):
        assert list_headers("") == []

    def test_returns_headers_of_all_depths(self):
        text = "# H1\n## H2\n### H3\n#### H4\n"
        result = list_headers(text)
        assert result == ["# H1", "## H2", "### H3", "#### H4"]

    def test_max_depth_filters_deep_headers(self):
        text = "# H1\n## H2\n### H3\n#### H4\n"
        result = list_headers(text, max_depth=2)
        assert result == ["# H1", "## H2"]

    def test_max_depth_none_returns_all(self):
        text = "# H1\n## H2\n### H3\n"
        result = list_headers(text, max_depth=None)
        assert result == ["# H1", "## H2", "### H3"]

    def test_max_depth_1_returns_only_h1(self):
        text = "# H1\n## H2\n### H3\n"
        result = list_headers(text, max_depth=1)
        assert result == ["# H1"]


class TestExtractSection:
    def test_returns_heading_and_content(self):
        text = "# Title\n\nIntro text.\n\n## Summary\n\nSome summary content.\n\n## Next\n\nOther.\n"
        result = extract_section(text, "## Summary")
        assert result.startswith("## Summary")
        assert "Some summary content." in result
        assert "## Next" not in result

    def test_includes_subsections(self):
        text = read(SAMPLE_SPEC)
        result = extract_section(text, "## Access")
        assert "## Access" in result
        assert "### Users" in result
        assert "### Organizations" in result
        assert "### Managers" in result

    def test_stops_at_sibling_heading(self):
        text = read(SAMPLE_SPEC)
        result = extract_section(text, "## Access")
        assert "## Alerts" not in result

    def test_stops_at_parent_heading(self):
        text = "# Doc\n\n## Section\n\nContent.\n\n# NewDoc\n\nOther.\n"
        result = extract_section(text, "## Section")
        assert "# NewDoc" not in result

    def test_section_not_found_raises(self):
        text = read(SAMPLE_SPEC)
        with pytest.raises(ValueError, match="section not found"):
            extract_section(text, "## Nonexistent Section")

    def test_h1_section_captures_all_children(self):
        text = "# Doc\n\nIntro.\n\n## A\n\nA content.\n\n## B\n\nB content.\n"
        result = extract_section(text, "# Doc")
        assert "## A" in result
        assert "## B" in result
