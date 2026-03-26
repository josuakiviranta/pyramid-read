#!/usr/bin/env bash
# Stage 2b: Does pyramid-reader subagent type beat vanilla subagents? (haiku subs, skill disabled both sides)
# Hypothesis: pyramid-reader subagent wins on quality at lower sub cost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --no-skill \
  --vanilla-subagents vanilla \
  --vanilla-subagent-model haiku \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  "$@"
