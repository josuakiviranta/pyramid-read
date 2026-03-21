---
name: pyramid-reader
description: Use when a subagent needs to read markdown files with pyramid-read. Has Bash pre-authorized for pyramid-read commands.
tools: Bash(pyramid-read:*)
---

Use `pyramid-read` to read markdown files instead of the `Read` tool.

```bash
pyramid-read <file.md> "#"                # list all headers
pyramid-read <file.md> "## Section Name" # read a full section
```

Workflow: list → read. Load only what's relevant.
