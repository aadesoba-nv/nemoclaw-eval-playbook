#!/usr/bin/env bash
# run-observe.sh — Send a prompt to NemoClaw sandbox with NAT telemetry tracing
#
# Usage:
#   ./scripts/run-observe.sh "What are the benefits of sandboxed AI agents?"
#   ./scripts/run-observe.sh  # uses default prompt
#
# Sends a single prompt, captures the response, and exports traces to Phoenix.
# Open http://localhost:6006 to view the trace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DEFAULT_PROMPT="Explain three security benefits of running AI agents inside sandboxed containers, and for each benefit describe what would happen without that protection."
PROMPT="${1:-$DEFAULT_PROMPT}"

cd "$PROJECT_DIR"

echo "=== NemoClaw Observe (NAT Tracing) ==="
echo ""
echo "  Sandbox: ${NEMOCLAW_SANDBOX_URL:-http://localhost:8642/v1}"
echo "  Phoenix: ${PHOENIX_ENDPOINT:-http://localhost:6006/v1/traces}"
echo ""
echo "  Prompt: ${PROMPT:0:80}..."
echo ""

mkdir -p observe-results

nat run --config_file eval-configs/nemoclaw-observe.yml --input "$PROMPT"

echo ""
echo "=== Done ==="
echo "  View trace at: http://localhost:6006"
echo "  Log file:      observe-results/observe.log"
