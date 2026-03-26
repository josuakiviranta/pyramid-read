#!/usr/bin/env bash
# Stage 3b: Full combination — skill + pyramid-reader subs vs vanilla + vanilla subs (haiku subs)
# Hypothesis: skill+PR-subs(haiku) outperforms vanilla+vanilla-subs(haiku) at lower cost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --vanilla-subagents vanilla \
  --vanilla-subagent-model haiku \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  "$@"
