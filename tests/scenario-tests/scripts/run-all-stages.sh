#!/usr/bin/env bash
# Runs all 6 stage scripts sequentially. Pass any extra flags (e.g. --verbose, --docs-dir) and
# they will be forwarded to every stage script.
set -euo pipefail
export LC_NUMERIC=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOGS_DIR"
SUMMARY_FILE="$LOGS_DIR/run-all-$(date +%Y-%m-%d-%H%M%S).summary"

echo "Summary: $SUMMARY_FILE"

run_stage() {
  local num="$1" label="$2" script="$3"
  shift 3
  echo ""
  echo "════════════════════════════════════════════════"
  echo "  STAGE ${num}: ${label}"
  echo "════════════════════════════════════════════════"
  "$SCRIPT_DIR/$script" --metrics-log "$SUMMARY_FILE" --stage-id "$num" "$@"
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

# ── Cross-stage summary table ──────────────────────────────
table=$(
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
  echo ""
  printf "  %-6s  %-5s  %-20s  %-20s  %-8s  %-16s  %-16s  %s\n" \
    "Stage" "Scen" "Vanilla-read cost" "Pyramid-read cost" "Delta%" \
    "Vanilla-read wins" "Pyramid-read wins" "Tie"
  echo "  ──────────────────────────────────────────────────────────────────────────────────────────────────────"
  grep "^STAGE_STATS:" "$SUMMARY_FILE" | while IFS=: read -r _ id scen v_cost p_cost dpct v_wins p_wins tie; do
    v_cost_fmt=$(printf "%.4f" "$v_cost")
    p_cost_fmt=$(printf "%.4f" "$p_cost")
    printf "  %-6s  %-5s  \$%-19s  \$%-19s  %-8s  %-16s  %-16s  %s\n" \
      "$id" "$scen" "$v_cost_fmt" "$p_cost_fmt" "${dpct}%" "$v_wins" "$p_wins" "$tie"
  done
  echo "════════════════════════════════════════════════"
)

echo "$table"
echo "$table" >> "$SUMMARY_FILE"
echo ""
echo "Summary: $SUMMARY_FILE"
