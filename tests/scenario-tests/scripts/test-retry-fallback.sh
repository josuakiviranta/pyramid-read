#!/usr/bin/env bash
# Unit tests for the empty-message retry logic in test-lookup-scenarios.sh.
# Stubs out run_scenario and extract_metrics — no Claude calls made.
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ── Stubs ──────────────────────────────────────────────────────────────────────

# Tracks how many times run_scenario was called in each test
call_count=0
# Response to return on the FIRST call; second call always returns SECOND_RESPONSE
FIRST_RESPONSE=""
SECOND_RESPONSE="Real answer on retry."

run_scenario() {
  call_count=$((call_count + 1))
  LAST_STREAM_FILE=$(mktemp)
  LAST_SESSION_FILE=""
}

extract_metrics() {
  if [ "$call_count" -eq 1 ]; then
    METRIC_RESPONSE="$FIRST_RESPONSE"
  else
    METRIC_RESPONSE="$SECOND_RESPONSE"
  fi
  METRIC_COST=0; METRIC_INPUT=0; METRIC_OUTPUT=0
}

patch_subagent()   { :; }
unpatch_subagent() { :; }

# ── Retry block (vanilla) — copied verbatim from test-lookup-scenarios.sh ──────

run_vanilla_with_retry() {
  local vanilla_prompt="$1"
  local vanilla_model="$2"

  run_scenario "$vanilla_prompt" "$vanilla_model"
  vanilla_stream="$LAST_STREAM_FILE"; v_session="$LAST_SESSION_FILE"
  extract_metrics "$vanilla_stream"
  v_cost="$METRIC_COST"; v_input="$METRIC_INPUT"; v_output="$METRIC_OUTPUT"; v_response="$METRIC_RESPONSE"
  rm -f "$vanilla_stream"

  if [ -n "$VANILLA_SUBAGENTS" ] && printf '%s' "$v_response" | grep -qi "came through empty\|what would you like help with"; then
    patch_subagent "$VANILLA_SUBAGENTS" "$VANILLA_SUBAGENT_MODEL"
    run_scenario "$vanilla_prompt" "$vanilla_model"
    vanilla_stream="$LAST_STREAM_FILE"; v_session="$LAST_SESSION_FILE"
    unpatch_subagent "$VANILLA_SUBAGENTS"
    extract_metrics "$vanilla_stream"
    v_cost="$METRIC_COST"; v_input="$METRIC_INPUT"; v_output="$METRIC_OUTPUT"; v_response="$METRIC_RESPONSE"
    rm -f "$vanilla_stream"
  fi
}

# ── Retry block (skill) — copied verbatim from test-lookup-scenarios.sh ────────

run_skill_with_retry() {
  local skill_prompt="$1"
  local skill_model="$2"

  run_scenario "$skill_prompt" "$skill_model"
  skill_stream="$LAST_STREAM_FILE"; s_session="$LAST_SESSION_FILE"
  extract_metrics "$skill_stream"
  s_cost="$METRIC_COST"; s_input="$METRIC_INPUT"; s_output="$METRIC_OUTPUT"; s_response="$METRIC_RESPONSE"
  rm -f "$skill_stream"

  if printf '%s' "$s_response" | grep -qi "came through empty\|what would you like help with"; then
    [ -n "$SKILL_SUBAGENTS" ] && patch_subagent "$SKILL_SUBAGENTS" "$SKILL_SUBAGENT_MODEL"
    run_scenario "$skill_prompt" "$skill_model"
    skill_stream="$LAST_STREAM_FILE"; s_session="$LAST_SESSION_FILE"
    [ -n "$SKILL_SUBAGENTS" ] && unpatch_subagent "$SKILL_SUBAGENTS"
    extract_metrics "$skill_stream"
    s_cost="$METRIC_COST"; s_input="$METRIC_INPUT"; s_output="$METRIC_OUTPUT"; s_response="$METRIC_RESPONSE"
    rm -f "$skill_stream"
  fi
}

# ── Helpers ────────────────────────────────────────────────────────────────────

reset() {
  call_count=0
  v_response=""; s_response=""
  VANILLA_SUBAGENTS=""; VANILLA_SUBAGENT_MODEL=""
  SKILL_SUBAGENTS="";   SKILL_SUBAGENT_MODEL=""
}

# ── Tests ──────────────────────────────────────────────────────────────────────

echo "vanilla retry:"

reset
FIRST_RESPONSE="Your message came through empty."
VANILLA_SUBAGENTS="vanilla"; VANILLA_SUBAGENT_MODEL="sonnet"
run_vanilla_with_retry "q" "sonnet"
[ "$call_count" -eq 2 ] && [ "$v_response" = "$SECOND_RESPONSE" ] \
  && pass "retries on 'came through empty' and updates v_response" \
  || fail "retries on 'came through empty' and updates v_response  (calls=$call_count response='$v_response')"

reset
FIRST_RESPONSE="Hi there! What would you like help with today?"
VANILLA_SUBAGENTS="vanilla"; VANILLA_SUBAGENT_MODEL="sonnet"
run_vanilla_with_retry "q" "sonnet"
[ "$call_count" -eq 2 ] && [ "$v_response" = "$SECOND_RESPONSE" ] \
  && pass "retries on 'what would you like help with'" \
  || fail "retries on 'what would you like help with'  (calls=$call_count response='$v_response')"

reset
FIRST_RESPONSE="Here is a normal answer."
VANILLA_SUBAGENTS="vanilla"; VANILLA_SUBAGENT_MODEL="sonnet"
run_vanilla_with_retry "q" "sonnet"
[ "$call_count" -eq 1 ] && [ "$v_response" = "Here is a normal answer." ] \
  && pass "does NOT retry on normal response" \
  || fail "does NOT retry on normal response  (calls=$call_count response='$v_response')"

reset
FIRST_RESPONSE="Your message came through empty."
VANILLA_SUBAGENTS=""   # no subagents → retry must not fire
run_vanilla_with_retry "q" "sonnet"
[ "$call_count" -eq 1 ] \
  && pass "does NOT retry when VANILLA_SUBAGENTS is unset" \
  || fail "does NOT retry when VANILLA_SUBAGENTS is unset  (calls=$call_count)"

echo ""
echo "skill retry:"

reset
FIRST_RESPONSE="Your message came through empty."
run_skill_with_retry "q" "sonnet"
[ "$call_count" -eq 2 ] && [ "$s_response" = "$SECOND_RESPONSE" ] \
  && pass "retries on 'came through empty' and updates s_response" \
  || fail "retries on 'came through empty' and updates s_response  (calls=$call_count response='$s_response')"

reset
FIRST_RESPONSE="Hi there! What would you like help with today?"
run_skill_with_retry "q" "sonnet"
[ "$call_count" -eq 2 ] && [ "$s_response" = "$SECOND_RESPONSE" ] \
  && pass "retries on 'what would you like help with'" \
  || fail "retries on 'what would you like help with'  (calls=$call_count response='$s_response')"

reset
FIRST_RESPONSE="Here is a normal answer."
run_skill_with_retry "q" "sonnet"
[ "$call_count" -eq 1 ] && [ "$s_response" = "Here is a normal answer." ] \
  && pass "does NOT retry on normal response" \
  || fail "does NOT retry on normal response  (calls=$call_count response='$s_response')"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "Results: $((PASS + FAIL)) tests — $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
