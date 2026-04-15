#!/usr/bin/env bash
# extract-sandbox-auth.sh — Get the API key and URL from a running NemoClaw sandbox
#
# Usage:
#   ./scripts/extract-sandbox-auth.sh [sandbox-name]
#   eval $(./scripts/extract-sandbox-auth.sh my-assistant)  # sets env vars
#
# Outputs export commands for NEMOCLAW_API_KEY and NEMOCLAW_SANDBOX_URL.

set -euo pipefail

SANDBOX_NAME="${1:-}"

if [ -z "$SANDBOX_NAME" ]; then
  echo "Usage: $0 <sandbox-name>" >&2
  echo "" >&2
  echo "Lists available sandboxes:" >&2
  if command -v openshell &>/dev/null; then
    openshell sandbox list 2>/dev/null || echo "  (openshell not available)" >&2
  elif command -v nemoclaw &>/dev/null; then
    echo "  Run: nemoclaw <name> status" >&2
  fi
  exit 1
fi

# Try to extract API key from sandbox
API_KEY=""
if command -v openshell &>/dev/null; then
  API_KEY=$(openshell sandbox exec "$SANDBOX_NAME" -- printenv API_SERVER_KEY 2>/dev/null || true)
fi

if [ -z "$API_KEY" ]; then
  echo "# Could not extract API_SERVER_KEY from sandbox '$SANDBOX_NAME'" >&2
  echo "# Try manually:" >&2
  echo "#   nemoclaw $SANDBOX_NAME connect" >&2
  echo "#   echo \$API_SERVER_KEY" >&2
  echo "" >&2
  echo "export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1"
  echo "export NEMOCLAW_API_KEY=  # Set manually"
else
  echo "export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1"
  echo "export NEMOCLAW_API_KEY=$API_KEY"
fi
