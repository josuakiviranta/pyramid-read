#!/usr/bin/env bash
# Stage 3d: Does skill(sonnet) + cheap haiku PR-subs beat vanilla sonnet + sonnet vanilla-subs?
# Hypothesis: the skill reduces token usage enough that haiku PR-subs keep quality up while cutting cost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --vanilla-model sonnet \
  --vanilla-subagents vanilla \
  --skill-model sonnet \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  "$@"
