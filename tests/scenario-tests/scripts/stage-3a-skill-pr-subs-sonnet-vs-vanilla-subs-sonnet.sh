#!/usr/bin/env bash
# Stage 3a: Full combination — skill + pyramid-reader subs vs vanilla + vanilla subs (sonnet subs)
# Hypothesis: skill+PR-subs outperforms vanilla+vanilla-subs on both quality and cost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --vanilla-subagents vanilla \
  --skill-subagents pyramid-reader \
  "$@"
