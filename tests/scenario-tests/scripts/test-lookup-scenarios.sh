#!/usr/bin/env bash
set -euo pipefail
export LC_NUMERIC=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$HOME/.claude/skills/pyramid-read"
SKILL_BAK="${SKILL_DIR}.bak"

# Defaults
DOCS_DIR="$SCRIPT_DIR/../test-specs"
PROMPTS_DIR="$SCRIPT_DIR/../tests-prompts"
VERBOSE=0
VANILLA_MODEL=sonnet
SKILL_MODEL=sonnet
VANILLA_SUBAGENTS=""         # "" | "vanilla" | "pyramid-reader"
VANILLA_SUBAGENT_MODEL=""    # defaults to VANILLA_MODEL if empty
SKILL_SUBAGENTS=""           # "" | "vanilla" | "pyramid-reader"
SKILL_SUBAGENT_MODEL=""      # defaults to SKILL_MODEL if empty
CUSTOM_SUBAGENT_LAUNCH_PROMPT=""
NO_SKILL=0
METRICS_LOG=""
STAGE_ID=""
LOGS_DIR="$SCRIPT_DIR/../logs"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)/.claude/agents"
SESSIONS_DIR="$HOME/.claude/projects/$(echo "$SCRIPT_DIR" | sed 's|/|-|g')"

usage() {
  echo "Usage: $0 [options]"
  echo "  --docs-dir                  Directory with markdown docs (default: test-specs/)"
  echo "  --prompts-dir               Directory with scenario .txt files (default: tests-prompts/)"
  echo "  --vanilla-model MODEL       Model for vanilla-read run (default: sonnet)"
  echo "  --skill-model MODEL         Model for pyramid-read run (default: sonnet)"
  echo "  --haiku                     Shorthand: set both main models to haiku"
  echo "  --vanilla-subagents TYPE    Enable subagents for vanilla side: vanilla|pyramid-reader"
  echo "  --vanilla-subagent-model M  Model for vanilla side subagents (default: vanilla model)"
  echo "  --skill-subagents TYPE      Enable subagents for skill side: vanilla|pyramid-reader"
  echo "  --skill-subagent-model M    Model for skill side subagents (default: skill model)"
  echo "  --subagent-launch-prompt T  Override subagent instruction appended to prompt"
  echo "  --no-skill                  Disable skill on both sides (for subagent-type comparison)"
  echo "  --logs-dir PATH             Directory for log files (default: logs/ next to scripts/)"
  echo "  --metrics-log FILE          Append metrics-only output to FILE (used by run-all-stages.sh)"
  echo "  --stage-id ID               Stage identifier written to metrics log (e.g. 1a)"
  echo "  --verbose                   Show full claude output"
  exit "${1:-1}"
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --docs-dir)                 DOCS_DIR="$2"; shift 2 ;;
    --prompts-dir)              PROMPTS_DIR="$2"; shift 2 ;;
    --vanilla-model)            VANILLA_MODEL="$2"; shift 2 ;;
    --skill-model)              SKILL_MODEL="$2"; shift 2 ;;
    --haiku)                    VANILLA_MODEL=haiku; SKILL_MODEL=haiku; shift ;;
    --vanilla-subagents)        VANILLA_SUBAGENTS="$2"; shift 2 ;;
    --vanilla-subagent-model)   VANILLA_SUBAGENT_MODEL="$2"; shift 2 ;;
    --skill-subagents)          SKILL_SUBAGENTS="$2"; shift 2 ;;
    --skill-subagent-model)     SKILL_SUBAGENT_MODEL="$2"; shift 2 ;;
    --subagent-launch-prompt)   CUSTOM_SUBAGENT_LAUNCH_PROMPT="$2"; shift 2 ;;
    --no-skill)                 NO_SKILL=1; shift ;;
    --logs-dir)                 LOGS_DIR="$2"; shift 2 ;;
    --metrics-log)              METRICS_LOG="$2"; shift 2 ;;
    --stage-id)                 STAGE_ID="$2"; shift 2 ;;
    --verbose)                  VERBOSE=1; shift ;;
    -h|--help)                  usage 0 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

LOG_FILE="$LOGS_DIR/test-results-$(date +%Y-%m-%d-%H%M%S).log"

# Resolve subagent model defaults and config labels
VANILLA_SUBAGENT_MODEL="${VANILLA_SUBAGENT_MODEL:-$VANILLA_MODEL}"
SKILL_SUBAGENT_MODEL="${SKILL_SUBAGENT_MODEL:-$SKILL_MODEL}"

build_config_label() {
  local main_model="$1" sub_type="$2" sub_model="$3"
  if [ -n "$sub_type" ]; then
    printf "%s [%s subs: %s]" "$main_model" "$sub_type" "$sub_model"
  else
    printf "%s" "$main_model"
  fi
}

VANILLA_LABEL=$(build_config_label "$VANILLA_MODEL" "$VANILLA_SUBAGENTS" "$VANILLA_SUBAGENT_MODEL")
SKILL_LABEL=$(build_config_label "$SKILL_MODEL" "$SKILL_SUBAGENTS" "$SKILL_SUBAGENT_MODEL")

get_subagent_prompt() {
  local sub_type="$1"
  if [ -n "$CUSTOM_SUBAGENT_LAUNCH_PROMPT" ]; then
    echo "$CUSTOM_SUBAGENT_LAUNCH_PROMPT"
  elif [ "$sub_type" = "pyramid-reader" ]; then
    echo "Use a pyramid-reader subagent for this lookup task. After the subagent returns its findings, synthesize them into a direct answer to the question above."
  elif [ "$sub_type" = "vanilla" ]; then
    echo "Use a vanilla-subagent subagent for this lookup task."
  fi
}

# Validate
[ -d "$DOCS_DIR" ]    || { echo "Error: docs dir not found: $DOCS_DIR"; exit 1; }
[ -d "$PROMPTS_DIR" ] || { echo "Error: prompts dir not found: $PROMPTS_DIR"; exit 1; }
[ -d "$SKILL_DIR" ]   || { echo "Error: pyramid-read skill not found at $SKILL_DIR"; exit 1; }
mkdir -p "$LOGS_DIR"

prompts=("$PROMPTS_DIR"/*.txt)
[ ${#prompts[@]} -gt 0 ] && [ -f "${prompts[0]}" ] || { echo "Error: no .txt files in $PROMPTS_DIR"; exit 1; }

echo "Docs:          $DOCS_DIR"
echo "Prompts:       $PROMPTS_DIR (${#prompts[@]} scenarios)"
echo "Vanilla-read:  $VANILLA_LABEL"
echo "Pyramid-read:  $SKILL_LABEL"
echo "Log:           $LOG_FILE"
echo ""

if [ -n "$METRICS_LOG" ]; then
  {
    echo "════════════════════════════════════════════════"
    echo "  STAGE ${STAGE_ID}"
    echo "════════════════════════════════════════════════"
    echo "Docs:         $DOCS_DIR"
    echo "Prompts:      $PROMPTS_DIR"
    echo "Vanilla-read: $VANILLA_LABEL"
    echo "Pyramid-read: $SKILL_LABEL"
    echo "Log:          $LOG_FILE"
    echo ""
  } >> "$METRICS_LOG"
fi

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

# patch_subagent <sub_type> <model>
# Modifies agent files so the named subagent type uses the given model.
patch_subagent() {
  local sub_type="$1"
  local model="$2"
  local agent_file="$AGENTS_DIR/${sub_type}.md"

  if [ "$sub_type" = "pyramid-reader" ]; then
    cp "$agent_file" "${agent_file}.bak"
    # Insert "model: MODEL" as the second line of the frontmatter (after opening ---)
    awk -v m="$model" 'NR==1 && /^---$/ { print; print "model: " m; next } { print }' \
      "${agent_file}.bak" > "$agent_file"
  elif [ "$sub_type" = "vanilla" ]; then
    # Create a minimal vanilla subagent agent file
    printf -- '---\nname: vanilla-subagent\nmodel: %s\ntools: Read,Glob,Grep\n---\nRead documentation files to answer questions. Use the Read, Glob, and Grep tools. Load only what is relevant.\n' \
      "$model" > "$agent_file"
  fi
}

# unpatch_subagent <sub_type>
unpatch_subagent() {
  local sub_type="$1"
  local agent_file="$AGENTS_DIR/${sub_type}.md"

  if [ "$sub_type" = "pyramid-reader" ] && [ -f "${agent_file}.bak" ]; then
    mv "${agent_file}.bak" "$agent_file"
  elif [ "$sub_type" = "vanilla" ] && [ -f "$agent_file" ]; then
    rm -f "$agent_file"
  fi
}

# run_scenario <prompt_text> <model>
# Sets LAST_STREAM_FILE to the stream-json temp file and LAST_SESSION_FILE to
# the .jsonl session created by this run. Must NOT be called via $() subshell
# or the globals won't propagate back to the caller.
LAST_STREAM_FILE=""
LAST_SESSION_FILE=""
run_scenario() {
  local prompt="$1"
  local model="$2"
  local stderr_file exit_code=0
  LAST_STREAM_FILE=$(mktemp)
  stderr_file=$(mktemp)

  printf '%s' "$prompt" | claude -p \
    --dangerously-skip-permissions \
    --output-format=stream-json \
    --model "$model" \
    > "$LAST_STREAM_FILE" 2>"$stderr_file" || exit_code=$?

  LAST_SESSION_FILE=$(ls -t "$SESSIONS_DIR"/*.jsonl 2>/dev/null | head -1 || true)

  if [ "$exit_code" -ne 0 ]; then
    echo "  [WARNING] claude exited with code $exit_code" >&2
    [ -s "$stderr_file" ] && cat "$stderr_file" >&2
  fi
  rm -f "$stderr_file"
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

# run_judge <docs_dir> <question> <response_a> <response_b>
# Sets JUDGE_WINNER (A|B|TIE) and JUDGE_REASON
run_judge() {
  local docs_dir="$1"
  local question="$2"
  local response_a="$3"
  local response_b="$4"

  local judge_prompt
  judge_prompt="You are comparing two AI responses to the same documentation lookup question.

DOCS DIR: ${docs_dir}
QUESTION: ${question}

=== RESPONSE A ===
${response_a}

=== RESPONSE B ===
${response_b}

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
    A)       echo "Vanilla-read win - \"${reason}\"" ;;
    B)       echo "Pyramid-read win - \"${reason}\"" ;;
    TIE)     echo "TIE - \"${reason}\"" ;;
    *)       echo "UNKNOWN - \"${reason}\"" ;;
  esac
}

# cost_delta <vanilla_cost> <skill_cost> → prints delta string
cost_delta() {
  echo "$1 $2" | awk '{
    delta = $2 - $1
    pct = ($1 > 0) ? (delta / $1 * 100) : 0
    if (delta > 0.000001)       printf "(Δ +$%.4f costlier) %+.2f%%", delta, pct
    else if (delta < -0.000001) printf "(Δ -$%.4f cheaper) %.2f%%", -delta, pct
    else                        printf "(Δ $0.0000 equal) 0.00%%"
  }'
}

fmt_num() {
  # Format integer with thousands separator
  printf "%'.0f" "$1" 2>/dev/null || printf "%d" "$1"
}

# ── Accumulators ──────────────────────────────────────────
total_vanilla_cost=0
total_skill_cost=0
total_vanilla_input=0
total_vanilla_output=0
total_skill_input=0
total_skill_output=0
cheaper_count=0
costlier_count=0
equal_count=0
judge_vanilla=0
judge_skill=0
judge_tie=0
scenario_count=0

# When NO_SKILL=1 the skill stays disabled for all scenarios; disable once here.
# The EXIT trap (restore_skill) will restore it on finish.
[ "$NO_SKILL" -eq 1 ] && disable_skill

# ── Per-scenario loop ─────────────────────────────────────
for prompt_file in "$PROMPTS_DIR"/*.txt; do
  [ -f "$prompt_file" ] || continue
  scenario_name=$(basename "$prompt_file" .txt)
  question=$(cat "$prompt_file")

  base_prompt="You have access to markdown documentation files in: ${DOCS_DIR}

Answer the following question using only the documentation in that directory:

${question}"

  # Append subagent instructions if enabled for each side
  if [ -n "$VANILLA_SUBAGENTS" ]; then
    vanilla_prompt="${base_prompt}

$(get_subagent_prompt "$VANILLA_SUBAGENTS")"
  else
    vanilla_prompt="$base_prompt"
  fi

  if [ -n "$SKILL_SUBAGENTS" ]; then
    skill_prompt="${base_prompt}

$(get_subagent_prompt "$SKILL_SUBAGENTS")"
  else
    skill_prompt="$base_prompt"
  fi

  echo "━━━ ${scenario_name} ━━━"
  echo "Prompt: \"${question}\""

  # ── Vanilla run (skill disabled) ──
  [ "$NO_SKILL" -eq 0 ] && disable_skill
  [ -n "$VANILLA_SUBAGENTS" ] && patch_subagent "$VANILLA_SUBAGENTS" "$VANILLA_SUBAGENT_MODEL"
  run_scenario "$vanilla_prompt" "$VANILLA_MODEL"
  vanilla_stream="$LAST_STREAM_FILE"
  v_session="$LAST_SESSION_FILE"
  [ -n "$VANILLA_SUBAGENTS" ] && unpatch_subagent "$VANILLA_SUBAGENTS"
  [ "$NO_SKILL" -eq 0 ] && enable_skill
  extract_metrics "$vanilla_stream"
  v_cost="$METRIC_COST"
  v_input="$METRIC_INPUT"
  v_output="$METRIC_OUTPUT"
  v_response="$METRIC_RESPONSE"
  rm -f "$vanilla_stream"

  # ── Skill run ──
  [ -n "$SKILL_SUBAGENTS" ] && patch_subagent "$SKILL_SUBAGENTS" "$SKILL_SUBAGENT_MODEL"
  run_scenario "$skill_prompt" "$SKILL_MODEL"
  skill_stream="$LAST_STREAM_FILE"
  s_session="$LAST_SESSION_FILE"
  [ -n "$SKILL_SUBAGENTS" ] && unpatch_subagent "$SKILL_SUBAGENTS"
  extract_metrics "$skill_stream"
  s_cost="$METRIC_COST"
  s_input="$METRIC_INPUT"
  s_output="$METRIC_OUTPUT"
  s_response="$METRIC_RESPONSE"
  rm -f "$skill_stream"

  # Retry once if the model returned the empty-message fallback (non-deterministic
  # behaviour after Agent tool_result where Claude mistakes a system-reminder
  # injection for an empty user message).
  if printf '%s' "$s_response" | grep -qi "came through empty\|what would you like help with"; then
    echo "  [RETRY] Pyramid-read got empty-message fallback, retrying once..." >&2
    [ -n "$SKILL_SUBAGENTS" ] && patch_subagent "$SKILL_SUBAGENTS" "$SKILL_SUBAGENT_MODEL"
    run_scenario "$skill_prompt" "$SKILL_MODEL"
    skill_stream="$LAST_STREAM_FILE"
    s_session="$LAST_SESSION_FILE"
    [ -n "$SKILL_SUBAGENTS" ] && unpatch_subagent "$SKILL_SUBAGENTS"
    extract_metrics "$skill_stream"
    s_cost="$METRIC_COST"
    s_input="$METRIC_INPUT"
    s_output="$METRIC_OUTPUT"
    s_response="$METRIC_RESPONSE"
    rm -f "$skill_stream"
  fi

  # ── Judge — blind random assignment ──
  if (( RANDOM % 2 == 0 )); then
    vanilla_is_a=1
    judge_a_response="$v_response"
    judge_b_response="$s_response"
  else
    vanilla_is_a=0
    judge_a_response="$s_response"
    judge_b_response="$v_response"
  fi
  run_judge "$DOCS_DIR" "$question" "$judge_a_response" "$judge_b_response"

  # Translate A/B winner back to vanilla/skill
  JUDGE_ASSIGNMENT="vanilla=A  pyramid=B"
  if [ "$vanilla_is_a" -eq 0 ]; then
    JUDGE_ASSIGNMENT="vanilla=B  pyramid=A"
    case "$JUDGE_WINNER" in
      A) JUDGE_WINNER=B ;;
      B) JUDGE_WINNER=A ;;
    esac
  fi

  verdict=$(format_verdict "$JUDGE_WINNER" "$JUDGE_REASON")

  # ── Delta ──
  delta_str=$(cost_delta "$v_cost" "$s_cost")

  # ── Print ──
  side_a_label="Vanilla-read"
  side_b_label="Pyramid-read"
  printf "  %s (%s):  in=%s  out=%s  cost=\$%.4f\n" \
    "$side_a_label" "$VANILLA_LABEL" "$(fmt_num "$v_input")" "$(fmt_num "$v_output")" "$v_cost"
  printf "  %s (%s):  in=%s  out=%s  cost=\$%.4f  %s\n" \
    "$side_b_label" "$SKILL_LABEL" "$(fmt_num "$s_input")" "$(fmt_num "$s_output")" "$s_cost" "$delta_str"
  echo "  LLM-judge:     ${verdict}"
  [ -n "$v_session" ] && echo "  Session (vanilla): $v_session"
  [ -n "$s_session" ] && echo "  Session (pyramid): $s_session"
  echo ""

  # ── Metrics log (no prompts or responses) ──
  if [ -n "$METRICS_LOG" ]; then
    {
      echo "  ${scenario_name}"
      printf "    Vanilla-read (%s):  in=%s  out=%s  cost=\$%.4f\n" \
        "$VANILLA_LABEL" "$(fmt_num "$v_input")" "$(fmt_num "$v_output")" "$v_cost"
      printf "    Pyramid-read (%s):  in=%s  out=%s  cost=\$%.4f  %s\n" \
        "$SKILL_LABEL" "$(fmt_num "$s_input")" "$(fmt_num "$s_output")" "$s_cost" "$delta_str"
      echo "    Judge: ${verdict}"
      echo ""
    } >> "$METRICS_LOG"
  fi

  # ── Log ──
  {
    echo "━━━ ${scenario_name} ━━━"
    echo "Prompt: \"${question}\""
    echo ""
    echo "VANILLA RESPONSE:"
    echo "$v_response"
    echo ""
    echo "PYRAMID-READ RESPONSE:"
    echo "$s_response"
    echo ""
    echo "METRICS: vanilla-read (${VANILLA_LABEL}) cost=\$${v_cost} in=${v_input} out=${v_output}"
    echo "METRICS: pyramid-read (${SKILL_LABEL}) cost=\$${s_cost} in=${s_input} out=${s_output}"
    echo "JUDGE: $verdict"
    [ -n "$v_session" ] && echo "SESSION: vanilla-read $v_session"
    [ -n "$s_session" ] && echo "SESSION: pyramid-read $s_session"
    echo ""
  } >> "$LOG_FILE"

  # ── Accumulators ──
  total_vanilla_cost=$(echo "$total_vanilla_cost + ${v_cost:-0}" | bc)
  total_skill_cost=$(echo "$total_skill_cost + ${s_cost:-0}" | bc)
  total_vanilla_input=$((total_vanilla_input + ${v_input:-0}))
  total_vanilla_output=$((total_vanilla_output + ${v_output:-0}))
  total_skill_input=$((total_skill_input + ${s_input:-0}))
  total_skill_output=$((total_skill_output + ${s_output:-0}))

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
  pct = ($1 > 0) ? (delta / $1 * 100) : 0
  if (delta > 0.000001)       printf "+$%.4f  (pyramid-read costlier overall)  %+.2f%%", delta, pct
  else if (delta < -0.000001) printf "-$%.4f  (pyramid-read cheaper overall)  %.2f%%", -delta, pct
  else                        printf "$0.0000  (equal overall)  0.00%%"
}')

side_a_label="Vanilla-read"
side_b_label="Pyramid-read"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${scenario_count} scenarios"
printf "  %s total cost: \$%.4f\n" "$side_a_label" "$total_vanilla_cost"
printf "  %s total cost: \$%.4f\n" "$side_b_label" "$total_skill_cost"
echo "  Net delta:               ${net_delta}"
echo ""
echo "  Cost breakdown:"
echo "    pyramid-read cheaper:  ${cheaper_count} scenarios"
echo "    pyramid-read costlier: ${costlier_count} scenarios"
echo "    equal:                 ${equal_count} scenarios"
echo ""
echo "  LLM-judge -> accuracy, completeness, and relevance:"
echo "    ${side_b_label} wins:  ${judge_skill} scenarios"
echo "    ${side_a_label} wins:  ${judge_vanilla} scenarios"
echo "    Tie:                ${judge_tie} scenarios"
echo ""
echo "  Log: ${LOG_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$METRICS_LOG" ]; then
  delta_pct=$(echo "$total_vanilla_cost $total_skill_cost" | awk '{
    pct = ($1 > 0) ? (($2 - $1) / $1 * 100) : 0
    printf "%.2f", pct
  }')
  {
    echo "  ─────────────────────────────────────"
    echo "  Results: ${scenario_count} scenarios"
    printf "    Vanilla-read total cost: \$%.4f\n" "$total_vanilla_cost"
    printf "    Pyramid-read total cost: \$%.4f  (%s%%)\n" "$total_skill_cost" "$delta_pct"
    echo "    Vanilla-read wins: ${judge_vanilla}  |  Pyramid-read wins: ${judge_skill}  |  Tie: ${judge_tie}"
    echo "  ─────────────────────────────────────"
    echo ""
    echo "STAGE_STATS:${STAGE_ID}:${scenario_count}:${total_vanilla_cost}:${total_skill_cost}:${delta_pct}:${judge_vanilla}:${judge_skill}:${judge_tie}:${total_vanilla_input}:${total_vanilla_output}:${total_skill_input}:${total_skill_output}"
    echo ""
  } >> "$METRICS_LOG"
fi
