#!/usr/bin/env bash
# Stage 3c: Can the full haiku pyramid-read stack (skill + PR-subs) match vanilla sonnet + vanilla-subs?
# Hypothesis: skill(haiku)+PR-subs(haiku) achieves comparable quality at significantly lower cost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --vanilla-model sonnet \
  --vanilla-subagents vanilla \
  --skill-model haiku \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  "$@"
