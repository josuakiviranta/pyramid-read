#!/usr/bin/env bash
# Stage 1b: Can haiku + pyramid-read skill match or beat vanilla sonnet?
# Hypothesis: haiku+skill is cheaper and competitive in quality vs sonnet baseline.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" \
  --skill-model haiku \
  "$@"
