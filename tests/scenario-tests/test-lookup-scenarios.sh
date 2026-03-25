#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$HOME/.claude/skills/pyramid-read"
SKILL_BAK="${SKILL_DIR}.bak"

# Defaults
DOCS_DIR="$SCRIPT_DIR/test-specs"
PROMPTS_DIR="$SCRIPT_DIR/tests-prompts"
VERBOSE=0
LOG_FILE="$SCRIPT_DIR/test-results-$(date +%Y-%m-%d-%H%M%S).log"

usage() {
  echo "Usage: $0 [--docs-dir PATH] [--prompts-dir PATH] [--verbose]"
  echo "  --docs-dir     Directory with markdown docs (default: specs/)"
  echo "  --prompts-dir  Directory with scenario .txt files (default: tests-prompts/)"
  echo "  --verbose      Show full claude output"
  exit "${1:-1}"
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-dir)    DOCS_DIR="$2"; shift 2 ;;
    --prompts-dir) PROMPTS_DIR="$2"; shift 2 ;;
    --verbose)     VERBOSE=1; shift ;;
    -h|--help)     usage 0 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Validate
[ -d "$DOCS_DIR" ]    || { echo "Error: docs dir not found: $DOCS_DIR"; exit 1; }
[ -d "$PROMPTS_DIR" ] || { echo "Error: prompts dir not found: $PROMPTS_DIR"; exit 1; }
[ -d "$SKILL_DIR" ]   || { echo "Error: pyramid-read skill not found at $SKILL_DIR"; exit 1; }

prompts=("$PROMPTS_DIR"/*.txt)
[ ${#prompts[@]} -gt 0 ] && [ -f "${prompts[0]}" ] || { echo "Error: no .txt files in $PROMPTS_DIR"; exit 1; }

echo "Docs:    $DOCS_DIR"
echo "Prompts: $PROMPTS_DIR (${#prompts[@]} scenarios)"
echo "Log:     $LOG_FILE"
echo ""

restore_skill() {
  if [ -d "$SKILL_BAK" ]; then
    mv "$SKILL_BAK" "$SKILL_DIR"
  fi
}
trap restore_skill EXIT

disable_skill() {
  if [ -d "$SKILL_BAK" ]; then
    echo "Error: stale skill backup found at $SKILL_BAK" >&2
    echo "A previous run may have been interrupted. Manually restore with:" >&2
    echo "  mv $SKILL_BAK $SKILL_DIR" >&2
    exit 1
  fi
  [ -d "$SKILL_DIR" ] && mv "$SKILL_DIR" "$SKILL_BAK"
}

enable_skill() {
  restore_skill
}

# run_scenario <prompt_text> → prints path to stream-json temp file
run_scenario() {
  local prompt="$1"
  local stream_file stderr_file exit_code=0
  stream_file=$(mktemp)
  stderr_file=$(mktemp)

  printf '%s' "$prompt" | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model sonnet \
    > "$stream_file" 2>"$stderr_file" || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    echo "  [WARNING] claude exited with code $exit_code" >&2
    [ -s "$stderr_file" ] && cat "$stderr_file" >&2
  fi
  rm -f "$stderr_file"
  echo "$stream_file"
}

# extract_metrics <stream_file> → sets METRIC_COST, METRIC_INPUT, METRIC_OUTPUT, METRIC_RESPONSE
extract_metrics() {
  local stream_file="$1"

  METRIC_COST=$(jq -rs '
    last | select(.type=="result") |
    .modelUsage | to_entries | map(.value.costUSD) | add // 0
  ' "$stream_file")

  METRIC_INPUT=$(jq -rs '
    last | select(.type=="result") | .usage.input_tokens // 0
  ' "$stream_file")

  METRIC_OUTPUT=$(jq -rs '
    last | select(.type=="result") | .usage.output_tokens // 0
  ' "$stream_file")

  METRIC_RESPONSE=$(jq -rs '
    [.[] | select(.type=="assistant") |
     .message.content[]? | select(.type=="text") | .text] | join("")
  ' "$stream_file")
}

# run_judge <docs_dir> <question> <vanilla_response> <skill_response>
# Sets JUDGE_WINNER (A|B|TIE) and JUDGE_REASON
run_judge() {
  local docs_dir="$1"
  local question="$2"
  local vanilla_response="$3"
  local skill_response="$4"

  local judge_prompt
  judge_prompt="You are comparing two AI responses to the same documentation lookup question.

DOCS DIR: ${docs_dir}
QUESTION: ${question}

=== RESPONSE A (vanilla, no pyramid-read skill) ===
${vanilla_response}

=== RESPONSE B (with pyramid-read skill) ===
${skill_response}

Which response better answers the question? Consider accuracy, completeness, and relevance.
Reply with exactly two lines and nothing else:
WINNER: A or B or TIE
REASON: one sentence"

  local judge_output judge_stream judge_stderr judge_exit=0
  judge_stream=$(mktemp)
  judge_stderr=$(mktemp)
  printf '%s' "$judge_prompt" | claude -p \
    --max-turns 1 \
    --output-format=stream-json \
    --model sonnet \
    > "$judge_stream" 2>"$judge_stderr" || judge_exit=$?
  if [ "$judge_exit" -ne 0 ]; then
    echo "  [WARNING] judge claude exited with code $judge_exit" >&2
    [ -s "$judge_stderr" ] && cat "$judge_stderr" >&2
  fi
  rm -f "$judge_stderr"
  judge_output=$(jq -rs '
    [.[] | select(.type=="assistant") |
     .message.content[]? | select(.type=="text") | .text] | join("")
  ' "$judge_stream")
  rm -f "$judge_stream"

  JUDGE_WINNER=$(printf '%s' "$judge_output" | grep '^WINNER:' | sed 's/WINNER: *//' | tr -d '[:space:]' || true)
  JUDGE_REASON=$(printf '%s' "$judge_output" | grep '^REASON:' | sed 's/REASON: *//' | sed 's/[[:space:]]*$//' || true)

  # Fallback if parse fails
  [ -z "$JUDGE_WINNER" ] && JUDGE_WINNER="UNKNOWN"
  [ -z "$JUDGE_REASON" ] && JUDGE_REASON="(could not parse judge output)"
  if [ "$JUDGE_WINNER" = "UNKNOWN" ]; then
    echo "  [WARNING] judge parse failed. Raw output: $(printf '%s' "$judge_output" | head -5)" >&2
  fi
}

format_verdict() {
  local winner="$1"
  local reason="$2"
  case "$winner" in
    A)       echo "VANILLA — \"${reason}\"" ;;
    B)       echo "PYRAMID-READ — \"${reason}\"" ;;
    TIE)     echo "TIE — \"${reason}\"" ;;
    *)       echo "UNKNOWN — \"${reason}\"" ;;
  esac
}

# cost_delta <vanilla_cost> <skill_cost> → prints delta string
cost_delta() {
  echo "$1 $2" | awk '{
    delta = $2 - $1
    if (delta > 0.000001)       printf "(Δ +$%.4f costlier)", delta
    else if (delta < -0.000001) printf "(Δ -$%.4f cheaper)", -delta
    else                        printf "(Δ $0.0000 equal)"
  }'
}

fmt_num() {
  # Format integer with thousands separator
  printf "%'.0f" "$1" 2>/dev/null || printf "%d" "$1"
}

# ── Accumulators ──────────────────────────────────────────
total_vanilla_cost=0
total_skill_cost=0
cheaper_count=0
costlier_count=0
equal_count=0
judge_vanilla=0
judge_skill=0
judge_tie=0
scenario_count=0

# ── Per-scenario loop ─────────────────────────────────────
for prompt_file in "$PROMPTS_DIR"/*.txt; do
  [ -f "$prompt_file" ] || continue
  scenario_name=$(basename "$prompt_file" .txt)
  question=$(cat "$prompt_file")

  full_prompt="You have access to markdown documentation files in: ${DOCS_DIR}

Answer the following question using only the documentation in that directory:

${question}"

  echo "━━━ ${scenario_name} ━━━"

  # ── Vanilla run (skill disabled) ──
  disable_skill
  vanilla_stream=$(run_scenario "$full_prompt")
  enable_skill
  extract_metrics "$vanilla_stream"
  v_cost="$METRIC_COST"
  v_input="$METRIC_INPUT"
  v_output="$METRIC_OUTPUT"
  v_response="$METRIC_RESPONSE"
  rm -f "$vanilla_stream"

  # ── Skill run ──
  skill_stream=$(run_scenario "$full_prompt")
  extract_metrics "$skill_stream"
  s_cost="$METRIC_COST"
  s_input="$METRIC_INPUT"
  s_output="$METRIC_OUTPUT"
  s_response="$METRIC_RESPONSE"
  rm -f "$skill_stream"

  # ── Judge ──
  run_judge "$DOCS_DIR" "$question" "$v_response" "$s_response"
  verdict=$(format_verdict "$JUDGE_WINNER" "$JUDGE_REASON")

  # ── Delta ──
  delta_str=$(cost_delta "$v_cost" "$s_cost")

  # ── Print ──
  printf "  Vanilla:       in=%s  out=%s  cost=\$%.4f\n" \
    "$(fmt_num "$v_input")" "$(fmt_num "$v_output")" "$v_cost"
  printf "  Pyramid-read:  in=%s  out=%s  cost=\$%.4f  %s\n" \
    "$(fmt_num "$s_input")" "$(fmt_num "$s_output")" "$s_cost" "$delta_str"
  echo "  Judge:         ${verdict}"
  echo ""

  # ── Log ──
  {
    echo "━━━ ${scenario_name} ━━━"
    echo "VANILLA RESPONSE:"
    echo "$v_response"
    echo ""
    echo "SKILL RESPONSE:"
    echo "$s_response"
    echo ""
    echo "METRICS: vanilla cost=\$${v_cost} in=${v_input} out=${v_output}"
    echo "METRICS: skill   cost=\$${s_cost} in=${s_input} out=${s_output}"
    echo "JUDGE: $verdict"
    echo ""
  } >> "$LOG_FILE"

  # ── Accumulators ──
  total_vanilla_cost=$(echo "$total_vanilla_cost + ${v_cost:-0}" | bc)
  total_skill_cost=$(echo "$total_skill_cost + ${s_cost:-0}" | bc)

  delta_sign=$(echo "${v_cost:-0} ${s_cost:-0}" | awk '{if ($2 < $1 - 0.000001) print "cheaper"; else if ($2 > $1 + 0.000001) print "costlier"; else print "equal"}')
  case "$delta_sign" in
    cheaper)  cheaper_count=$((cheaper_count + 1)) ;;
    costlier) costlier_count=$((costlier_count + 1)) ;;
    equal)    equal_count=$((equal_count + 1)) ;;
  esac

  case "$JUDGE_WINNER" in
    A)   judge_vanilla=$((judge_vanilla + 1)) ;;
    B)   judge_skill=$((judge_skill + 1)) ;;
    TIE) judge_tie=$((judge_tie + 1)) ;;
  esac

  scenario_count=$((scenario_count + 1))
done

# ── Summary ───────────────────────────────────────────────
net_delta=$(echo "$total_vanilla_cost $total_skill_cost" | awk '{
  delta = $2 - $1
  if (delta > 0.000001)       printf "+$%.4f  (pyramid-read costlier overall)", delta
  else if (delta < -0.000001) printf "-$%.4f  (pyramid-read cheaper overall)", -delta
  else                        printf "$0.0000  (equal overall)"
}')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${scenario_count} scenarios"
printf "  Vanilla total cost:      \$%.4f\n" "$total_vanilla_cost"
printf "  Pyramid-read total cost: \$%.4f\n" "$total_skill_cost"
echo "  Net delta:               ${net_delta}"
echo ""
echo "  Cost breakdown:"
echo "    pyramid-read cheaper:  ${cheaper_count} scenarios"
echo "    pyramid-read costlier: ${costlier_count} scenarios"
echo "    equal:                 ${equal_count} scenarios"
echo ""
echo "  Judge:  pyramid-read ${judge_skill} / vanilla ${judge_vanilla} / tie ${judge_tie}"
echo "  Log: ${LOG_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
