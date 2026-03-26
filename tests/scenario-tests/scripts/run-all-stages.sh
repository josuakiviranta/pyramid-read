#!/usr/bin/env bash
# Runs all 6 stage scripts sequentially. Pass any extra flags (e.g. --verbose, --docs-dir) and
# they will be forwarded to every stage script.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_stage() {
  local num="$1" label="$2" script="$3"
  echo ""
  echo "════════════════════════════════════════════════"
  echo "  STAGE ${num}: ${label}"
  echo "════════════════════════════════════════════════"
  "$SCRIPT_DIR/$script" "${@:4}"
}

run_stage "1a" "Skill (sonnet) vs Vanilla (sonnet) — no subagents" \
  "stage-1a-skill-sonnet-vs-vanilla-sonnet.sh" "$@"

run_stage "1b" "Skill (haiku) vs Vanilla (sonnet) — no subagents" \
  "stage-1b-skill-haiku-vs-vanilla-sonnet.sh" "$@"

run_stage "2a" "PR subagents (sonnet) vs Vanilla subagents (sonnet) — skill disabled both sides" \
  "stage-2a-pr-subs-sonnet-vs-vanilla-subs-sonnet.sh" "$@"

run_stage "2b" "PR subagents (haiku) vs Vanilla subagents (haiku) — skill disabled both sides" \
  "stage-2b-pr-subs-haiku-vs-vanilla-subs-haiku.sh" "$@"

run_stage "3a" "Skill+PR subs (sonnet) vs Vanilla+vanilla subs (sonnet) — full combination" \
  "stage-3a-skill-pr-subs-sonnet-vs-vanilla-subs-sonnet.sh" "$@"

run_stage "3b" "Skill+PR subs (haiku) vs Vanilla+vanilla subs (haiku) — full combination" \
  "stage-3b-skill-pr-subs-haiku-vs-vanilla-subs-haiku.sh" "$@"

echo ""
echo "════════════════════════════════════════════════"
echo "  ALL STAGES COMPLETE"
echo "  Stage legend:"
echo "    1a  Does the skill help at same model tier?"
echo "    1b  Can haiku+skill match vanilla sonnet?"
echo "    2a  Does PR subagent type beat vanilla subs? (sonnet)"
echo "    2b  Does PR subagent type beat vanilla subs? (haiku)"
echo "    3a  Skill+PR subs vs vanilla+vanilla subs? (sonnet)"
echo "    3b  Skill+PR subs vs vanilla+vanilla subs? (haiku)"
echo "════════════════════════════════════════════════"
