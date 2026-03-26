#!/usr/bin/env bash
# Stage 2c: Can vanilla haiku + PR-subs match vanilla sonnet + vanilla-subs? (skill off both sides)
# Hypothesis: haiku+PR-subs achieves comparable quality at lower cost than sonnet+vanilla-subs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --no-skill \
  --vanilla-model sonnet \
  --vanilla-subagents vanilla \
  --skill-model haiku \
  --skill-subagents pyramid-reader \
  --skill-subagent-model haiku \
  "$@"
