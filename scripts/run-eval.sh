#!/usr/bin/env bash
# run-eval.sh — Execute NAT evaluation against NemoClaw sandbox
#
# Usage:
#   ./scripts/run-eval.sh [--with-phoenix] [--dataset FILE] [--concurrency N]
#
# Environment variables:
#   NEMOCLAW_SANDBOX_URL  — Hermes API URL (default: http://localhost:8642/v1)
#   NEMOCLAW_API_KEY      — Hermes bearer token
#   NVIDIA_API_KEY        — NVIDIA endpoints key for judge LLM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

WITH_PHOENIX=false
DATASET=""
CONCURRENCY=""
OVERRIDES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-phoenix) WITH_PHOENIX=true; shift ;;
    --dataset) DATASET="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Select config
if [ "$WITH_PHOENIX" = true ]; then
  CONFIG="eval-configs/nemoclaw-eval-phoenix.yml"
  echo "=== Running NemoClaw eval with Phoenix tracing ==="
else
  CONFIG="eval-configs/nemoclaw-eval.yml"
  echo "=== Running NemoClaw eval ==="
fi

# Preflight checks
if [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "ERROR: NVIDIA_API_KEY not set. Required for judge LLM."
  echo "  export NVIDIA_API_KEY=<your-key-from-build.nvidia.com>"
  exit 1
fi

cd "$PROJECT_DIR"

# Build override args
if [ -n "$DATASET" ]; then
  OVERRIDES+=(--override eval.general.dataset.file_path "$DATASET")
fi

if [ -n "$CONCURRENCY" ]; then
  OVERRIDES+=(--override eval.general.max_concurrency "$CONCURRENCY")
fi

echo ""
echo "  Config:    $CONFIG"
echo "  Sandbox:   ${NEMOCLAW_SANDBOX_URL:-http://localhost:8642/v1}"
echo "  Dataset:   ${DATASET:-eval-datasets/combined.json (default)}"
echo ""

# Create output dir
mkdir -p eval-results

# Run evaluation
nat eval --config_file "$CONFIG" "${OVERRIDES[@]}"

echo ""
echo "=== Eval complete ==="
echo "  Results in: $PROJECT_DIR/eval-results/"
echo ""

# Summarize if output exists
if [ -f eval-results/workflow_output.json ]; then
  echo "--- Quick Summary ---"
  python3 -c "
import json, sys

# Print evaluator scores
for f in ['accuracy_output.json', 'groundedness_output.json', 'trajectory_output.json']:
    path = 'eval-results/' + f
    try:
        with open(path) as fh:
            data = json.load(fh)
        avg = data.get('average_score', data.get('average', 'N/A'))
        name = f.replace('_output.json', '')
        print(f'  {name}: {avg}')
    except FileNotFoundError:
        pass
    except Exception as e:
        print(f'  {f}: error reading ({e})', file=sys.stderr)
"
fi

echo ""
echo "Full results: ls eval-results/"
echo "Phoenix UI:   http://localhost:6006 (if running)"
