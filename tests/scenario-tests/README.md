# pyramid-read Lookup Scenario Tests

Compares Claude's documentation lookup quality and cost with vs without the pyramid-read skill.

## What It Tests

For each scenario prompt, the runner:
1. Runs the **vanilla-read** side (skill disabled) and records response + cost
2. Runs the **pyramid-read** side (skill enabled) and records response + cost
3. Calls an LLM judge to pick the better response (accuracy, completeness, relevance)
4. Reports cost delta, percentage difference, and judge verdict

Each side is independently configurable: main agent model, optional subagents (vanilla or pyramid-reader type), and subagent model.

## Prerequisites

- `claude` CLI installed and authenticated
- `jq` installed
- `bc` installed
- pyramid-read skill at `~/.claude/skills/pyramid-read/`

## Usage

### Stage scripts (recommended)

Six pre-configured stage scripts live in `scripts/`. Run them directly or use the harness to run all six sequentially:

```bash
# Run all 6 stages (forwards any extra flags to each stage)
./scripts/run-all-stages.sh
./scripts/run-all-stages.sh --docs-dir /path/to/docs
./scripts/run-all-stages.sh --docs-dir /path/to/docs --prompts-dir /path/to/prompts

# Individual stages
./scripts/stage-1a-skill-sonnet-vs-vanilla-sonnet.sh        # skill vs no-skill, same model
./scripts/stage-1b-skill-haiku-vs-vanilla-sonnet.sh         # haiku+skill vs vanilla sonnet
./scripts/stage-2a-pr-subs-sonnet-vs-vanilla-subs-sonnet.sh # PR-subs vs vanilla-subs (sonnet, no skill)
./scripts/stage-2b-pr-subs-haiku-vs-vanilla-subs-haiku.sh   # PR-subs vs vanilla-subs (haiku, no skill)
./scripts/stage-3a-skill-pr-subs-sonnet-vs-vanilla-subs-sonnet.sh  # full combo, sonnet
./scripts/stage-3b-skill-pr-subs-haiku-vs-vanilla-subs-haiku.sh    # full combo, haiku
```

### Direct runner

```bash
# Default: uses test-specs/ as docs, tests-prompts/ as prompts, both sides on sonnet
./scripts/test-lookup-scenarios.sh

# Custom docs and prompts directories
./scripts/test-lookup-scenarios.sh --docs-dir /path/to/your/docs
./scripts/test-lookup-scenarios.sh --prompts-dir /path/to/prompts

# Run both sides on haiku (cheaper, faster)
./scripts/test-lookup-scenarios.sh --haiku

# Set main models individually
./scripts/test-lookup-scenarios.sh --vanilla-model haiku --skill-model sonnet

# pyramid-reader subagents (haiku) on the skill side vs plain vanilla
./scripts/test-lookup-scenarios.sh --skill-subagents pyramid-reader --skill-subagent-model haiku

# Compare subagent types with skill disabled on both sides
./scripts/test-lookup-scenarios.sh \
  --no-skill \
  --vanilla-subagents vanilla \
  --skill-subagents pyramid-reader

# Verbose: shows full claude output
./scripts/test-lookup-scenarios.sh --verbose
```

### All flags

| Flag | Default | Description |
|------|---------|-------------|
| `--docs-dir PATH` | `test-specs/` | Directory with markdown docs |
| `--prompts-dir PATH` | `tests-prompts/` | Directory with scenario `.txt` files |
| `--vanilla-model MODEL` | `sonnet` | Main agent model for vanilla-read side |
| `--skill-model MODEL` | `sonnet` | Main agent model for pyramid-read side |
| `--haiku` | — | Shorthand: set both main models to haiku |
| `--vanilla-subagents TYPE` | — | Enable subagents on vanilla side: `vanilla` or `pyramid-reader` |
| `--vanilla-subagent-model M` | vanilla model | Model for vanilla side subagents |
| `--skill-subagents TYPE` | — | Enable subagents on skill side: `vanilla` or `pyramid-reader` |
| `--skill-subagent-model M` | skill model | Model for skill side subagents |
| `--subagent-launch-prompt T` | type-dependent | Override instruction appended to prompt when subagents are enabled |
| `--no-skill` | — | Disable skill on both sides (for subagent-type comparisons) |
| `--verbose` | — | Show full claude output |

## Adding Scenarios

Add a `.txt` file to `tests-prompts/`. The filename (without `.txt`) becomes the scenario name. Files are processed in alphabetical order.

## Output

Per-scenario:
```
━━━ 01-narrow-fact-lookup ━━━
Prompt: "what endpoints do i use to create and delete a todo"
  Vanilla-read (sonnet):                        in=2,847  out=312  cost=$0.0094
  Pyramid-read (haiku [pyramid-reader subs: haiku]):  in=891  out=287  cost=$0.0070  (Δ -$0.0024 cheaper) -25.53%
  LLM-judge:     Pyramid-read win - "More targeted answer, found the exact section"
```

Final summary:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Results: 4 scenarios
  Vanilla-read total cost: $0.0376
  Pyramid-read total cost: $0.0280
  Net delta:               -$0.0096  (pyramid-read cheaper overall)  -25.53%

  Cost breakdown:
    pyramid-read cheaper:  3 scenarios
    pyramid-read costlier: 1 scenarios
    equal:                 0 scenarios

  LLM-judge -> accuracy, completeness, and relevance:
    Pyramid-read wins:  3 scenarios
    Vanilla-read wins:  0 scenarios
    Tie:                1 scenarios

  Log: .../logs/test-results-2026-03-26-120000.log
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Full responses for both sides per scenario are saved to `logs/test-results-YYYY-MM-DD-HHMMSS.log`.
