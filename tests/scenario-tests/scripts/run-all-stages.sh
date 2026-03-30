#!/usr/bin/env bash
# Runs all 6 stage scripts sequentially. Pass any extra flags (e.g. --verbose, --docs-dir) and
# they will be forwarded to every stage script.
set -euo pipefail
export LC_NUMERIC=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/../logs"
RUN_DIR="$LOGS_DIR/run-$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$RUN_DIR"
SUMMARY_FILE="$RUN_DIR/run-all.summary"

echo "Run dir:  $RUN_DIR"
echo "Summary:  $SUMMARY_FILE"

run_stage() {
  local num="$1" label="$2" script="$3"
  shift 3
  echo ""
  echo "════════════════════════════════════════════════"
  echo "  STAGE ${num}: ${label}"
  echo "════════════════════════════════════════════════"
  "$SCRIPT_DIR/$script" --metrics-log "$SUMMARY_FILE" --stage-id "$num" --logs-dir "$RUN_DIR" "$@"
}

run_stage "1a" "Skill (sonnet) vs Vanilla (sonnet) — no subagents" \
  "stage-1a-skill-sonnet-vs-vanilla-sonnet.sh" "$@"

run_stage "1b" "Skill (haiku) vs Vanilla (sonnet) — no subagents" \
  "stage-1b-skill-haiku-vs-vanilla-sonnet.sh" "$@"

run_stage "2a" "PR subagents (sonnet) vs Vanilla subagents (sonnet) — skill disabled both sides" \
  "stage-2a-pr-subs-sonnet-vs-vanilla-subs-sonnet.sh" "$@"

run_stage "2b" "PR subagents (haiku) vs Vanilla subagents (haiku) — skill disabled both sides" \
  "stage-2b-pr-subs-haiku-vs-vanilla-subs-haiku.sh" "$@"

run_stage "2c" "vanilla+PR-subs (haiku) vs vanilla+vanilla-subs (sonnet) — cross-tier, skill disabled both sides" \
  "stage-2c-vanilla-haiku-pr-subs-vs-vanilla-sonnet-subs.sh" "$@"

run_stage "2d" "vanilla+PR-subs (haiku subs) vs vanilla+vanilla-subs (sonnet) — sonnet main, cheap subs, skill disabled" \
  "stage-2d-vanilla-sonnet-pr-subs-haiku-vs-vanilla-sonnet-subs.sh" "$@"

run_stage "3a" "Skill+PR subs (sonnet) vs Vanilla+vanilla subs (sonnet) — full combination" \
  "stage-3a-skill-pr-subs-sonnet-vs-vanilla-subs-sonnet.sh" "$@"

run_stage "3b" "Skill+PR subs (haiku) vs Vanilla+vanilla subs (haiku) — full combination" \
  "stage-3b-skill-pr-subs-haiku-vs-vanilla-subs-haiku.sh" "$@"

run_stage "3c" "skill+PR-subs (haiku) vs vanilla+vanilla-subs (sonnet) — full haiku stack vs vanilla sonnet" \
  "stage-3c-skill-haiku-pr-subs-vs-vanilla-sonnet-subs.sh" "$@"

run_stage "3d" "skill+PR-subs (haiku subs) vs vanilla+vanilla-subs (sonnet) — sonnet+skill, cheap subs vs full vanilla" \
  "stage-3d-skill-sonnet-pr-subs-haiku-vs-vanilla-sonnet-subs.sh" "$@"

# ── Cross-stage summary table ──────────────────────────────
table=$(
  echo ""
  echo "════════════════════════════════════════════════"
  echo "  ALL STAGES COMPLETE"
  echo "  Stage legend:"
  echo "    1a  skill(sonnet)          vs vanilla(sonnet)              — Does the pyramid-read skill improve quality at the same model tier?"
  echo "    1b  skill(haiku)           vs vanilla(sonnet)              — Can a cheaper model with the skill match a vanilla sonnet?"
  echo "    2a  vanilla+PR-subs(sonnet) vs vanilla+vanilla-subs(sonnet) — Do pyramid-reader subagents beat vanilla subagents with vanilla Claude? (skill off both sides)"
  echo "    2b  vanilla+PR-subs(haiku)  vs vanilla+vanilla-subs(haiku)  — Do pyramid-reader subagents beat vanilla subagents with vanilla Claude? (haiku tier, skill off both sides)"
  echo "    2c  vanilla+PR-subs(haiku)  vs vanilla+vanilla-subs(sonnet) — Can a haiku+PR-subs setup match vanilla sonnet+subs quality/cost? (skill off both sides)"
  echo "    2d  vanilla(sonnet)+PR-subs(haiku) vs vanilla(sonnet)+vanilla-subs(sonnet) — Does sonnet main with cheap haiku PR-subs beat sonnet+vanilla-subs? (skill off)"
  echo "    3a  skill+PR-subs(sonnet)  vs vanilla+vanilla-subs(sonnet) — Does the full pyramid-read stack beat a fully-vanilla setup? (sonnet)"
  echo "    3b  skill+PR-subs(haiku)   vs vanilla+vanilla-subs(haiku)  — Does the full pyramid-read stack beat a fully-vanilla setup? (haiku)"
  echo "    3c  skill(haiku)+PR-subs(haiku) vs vanilla(sonnet)+vanilla-subs(sonnet) — Can the full haiku pyramid-read stack match a vanilla sonnet+subs setup?"
  echo "    3d  skill(sonnet)+PR-subs(haiku) vs vanilla(sonnet)+vanilla-subs(sonnet) — Does skill+cheap haiku PR-subs beat vanilla sonnet+subs?"
  echo "════════════════════════════════════════════════"
  echo ""
  echo "  LLM-judge prompt (per scenario):"
  echo "    \"You are comparing two AI responses to the same documentation lookup question."
  echo "     QUESTION: <scenario prompt>"
  echo "     RESPONSE A / RESPONSE B  (randomly assigned per scenario — blind, no system names)"
  echo "     Which response better answers the question? Consider accuracy, completeness, and relevance."
  echo "     Reply with: WINNER: A or B or TIE / REASON: one sentence\""
  echo ""
  echo "  Column guide:"
  echo "    Scen    Number of scenarios run in this stage"
  echo "    v-cost  Total USD cost for the Vanilla-read side across all scenarios"
  echo "    pr-cost Total USD cost for the Pyramid-read side across all scenarios"
  echo "    Delta%  (pr-cost - v-cost) / v-cost x 100  (negative = pyramid-read cheaper)"
  echo "    v-wins  Scenarios where LLM judge picked Vanilla-read as the better answer"
  echo "    pr-wins Scenarios where LLM judge picked Pyramid-read as the better answer"
  echo "    Tie     Scenarios where LLM judge called it a tie"
  echo "    v-in    Total input tokens consumed by the Vanilla-read side"
  echo "    v-out   Total output tokens produced by the Vanilla-read side"
  echo "    pr-in   Total input tokens consumed by the Pyramid-read side"
  echo "    pr-out  Total output tokens produced by the Pyramid-read side"
  echo ""
  printf "  %-6s  %-5s  %-10s  %-10s  %-9s  %-7s  %-8s  %-4s  %-9s  %-8s  %-9s  %s\n" \
    "Stage" "Scen" "v-cost" "pr-cost" "Delta%" "v-wins" "pr-wins" "Tie" "v-in" "v-out" "pr-in" "pr-out"
  echo "  ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
  grep "^STAGE_STATS:" "$SUMMARY_FILE" | while IFS=: read -r _ id scen v_cost p_cost dpct v_wins p_wins tie v_in v_out p_in p_out; do
    v_cost_fmt=$(printf "%.4f" "$v_cost")
    p_cost_fmt=$(printf "%.4f" "$p_cost")
    v_in_fmt=$(printf "%'.0f" "$v_in" 2>/dev/null || printf "%d" "$v_in")
    v_out_fmt=$(printf "%'.0f" "$v_out" 2>/dev/null || printf "%d" "$v_out")
    p_in_fmt=$(printf "%'.0f" "$p_in" 2>/dev/null || printf "%d" "$p_in")
    p_out_fmt=$(printf "%'.0f" "$p_out" 2>/dev/null || printf "%d" "$p_out")
    printf "  %-6s  %-5s  \$%-9s  \$%-9s  %-9s  %-7s  %-8s  %-4s  %-9s  %-8s  %-9s  %s\n" \
      "$id" "$scen" "$v_cost_fmt" "$p_cost_fmt" "${dpct}%" "$v_wins" "$p_wins" "$tie" \
      "$v_in_fmt" "$v_out_fmt" "$p_in_fmt" "$p_out_fmt"
  done
  echo "════════════════════════════════════════════════"
)

echo "$table"
echo "$table" >> "$SUMMARY_FILE"
echo ""
echo "Run dir:  $RUN_DIR"
echo "Summary:  $SUMMARY_FILE"
