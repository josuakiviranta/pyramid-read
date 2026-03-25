# pyramid-read Lookup Scenario Tests

Compares Claude's documentation lookup quality and cost with vs without the pyramid-read skill.

## What It Tests

For each scenario prompt, the runner:
1. Disables the pyramid-read skill (vanilla mode, Bash allowed)
2. Runs `claude -p` and records response + cost
3. Re-enables the skill
4. Runs the same prompt again and records response + cost
5. Calls an LLM judge to pick the better response
6. Reports cost delta and judge verdict

## Prerequisites

- `claude` CLI installed and authenticated
- `jq` installed
- `bc` installed
- pyramid-read skill at `~/.claude/skills/pyramid-read/`

## Usage

```bash
# Default: uses loop-lab specs/ as docs
./test-lookup-scenarios.sh

# Custom docs directory
./test-lookup-scenarios.sh --docs-dir /path/to/your/docs

# Custom prompts directory
./test-lookup-scenarios.sh --prompts-dir /path/to/prompts

# Verbose: shows full claude output
./test-lookup-scenarios.sh --verbose
```

## Adding Scenarios

Add a `.txt` file to `tests-prompts/`. The filename (without `.txt`) becomes the scenario name. Files are processed in alphabetical order.

## Output

Per-scenario:
```
━━━ 01-narrow-fact-lookup ━━━
  Vanilla:       in=2,847  out=312  cost=$0.0094
  Pyramid-read:  in=891    out=287  cost=$0.0070  (Δ -$0.0024 cheaper)
  Judge:         PYRAMID-READ — "More targeted answer, found the exact section"
```

Final summary shows total costs, cost breakdown by direction, and judge win counts.

A full log with both responses per scenario is saved as `test-results-YYYY-MM-DD-HHMMSS.log`.
