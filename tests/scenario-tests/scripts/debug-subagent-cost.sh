#!/usr/bin/env bash
# Debug script: cheapest possible run with subagents to verify modelUsage cost accounting.
# Uses haiku for everything, 1 scenario only.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Single-scenario tmp prompts dir
PROMPTS_TMP=$(mktemp -d)
cp "$SCRIPT_DIR/../tests-prompts/01-narrow-fact-lookup.txt" "$PROMPTS_TMP/"
trap 'rm -rf "$PROMPTS_TMP"' EXIT

exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --haiku \
  --vanilla-subagents vanilla \
  --vanilla-subagent-model haiku \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  --prompts-dir "$PROMPTS_TMP" \
  "$@"
