#!/usr/bin/env bash
# Stage 1a: Does the pyramid-read skill help at the same model tier?
# Hypothesis: skill (sonnet) beats vanilla (sonnet) on quality and/or cost.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/test-lookup-scenarios.sh" "$@"
