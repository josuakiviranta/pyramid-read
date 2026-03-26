#!/usr/bin/env bash
# Stage 2d: Does sonnet main + cheap haiku PR-subs beat sonnet + sonnet vanilla-subs? (skill off both sides)
# Hypothesis: swapping sonnet vanilla-subs for haiku PR-subs reduces cost without hurting quality.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --no-skill \
  --vanilla-model sonnet \
  --vanilla-subagents vanilla \
  --skill-model sonnet \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  "$@"
