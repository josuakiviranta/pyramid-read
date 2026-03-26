#!/usr/bin/env bash
# Stage 2a: Does pyramid-reader subagent type beat vanilla subagents? (sonnet subs, skill disabled both sides)
# Hypothesis: pyramid-reader subagent wins on quality regardless of skill.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --no-skill \
  --vanilla-subagents vanilla \
  --skill-subagents pyramid-reader \
  "$@"
