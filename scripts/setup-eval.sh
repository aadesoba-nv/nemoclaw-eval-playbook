#!/usr/bin/env bash
# setup-eval.sh — Install NAT, start Phoenix, verify sandbox connectivity
#
# Usage:
#   ./scripts/setup-eval.sh [--sandbox-url URL] [--skip-phoenix]
#
# Environment variables (optional):
#   NEMOCLAW_SANDBOX_URL  — Hermes API URL (default: http://localhost:8642/v1)
#   NEMOCLAW_API_KEY      — Hermes bearer token (API_SERVER_KEY)
#   NVIDIA_API_KEY        — NVIDIA endpoints key for judge LLM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SANDBOX_URL="${NEMOCLAW_SANDBOX_URL:-http://localhost:8642/v1}"
SKIP_PHOENIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox-url) SANDBOX_URL="$2"; shift 2 ;;
    --skip-phoenix) SKIP_PHOENIX=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=== NemoClaw + NAT Eval Setup ==="
echo ""

# ── Step 1: Check Python ────────────────────────────────────────
echo "[1/5] Checking Python version..."
if ! command -v python3 &>/dev/null; then
  echo "  ERROR: python3 not found. NAT requires Python 3.11-3.13."
  exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Found Python $PYTHON_VERSION"

if python3 -c "import sys; exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
  echo "  OK"
else
  echo "  WARNING: NAT requires Python 3.11+. You have $PYTHON_VERSION."
fi

# ── Step 2: Install NAT ─────────────────────────────────────────
echo ""
echo "[2/5] Installing NVIDIA NeMo Agent Toolkit..."
if python3 -c "import nat" 2>/dev/null; then
  echo "  NAT already installed."
  NAT_VERSION=$(pip show nvidia-nat 2>/dev/null | grep Version | awk '{print $2}')
  echo "  Version: ${NAT_VERSION:-unknown}"
else
  echo "  Installing nvidia-nat with eval and phoenix extras..."
  pip install "nvidia-nat[eval,phoenix]"
  echo "  Done."
fi

# ── Step 3: Start Phoenix ───────────────────────────────────────
echo ""
echo "[3/5] Setting up Phoenix tracing dashboard..."
if [ "$SKIP_PHOENIX" = true ]; then
  echo "  Skipped (--skip-phoenix flag)."
else
  if docker ps 2>/dev/null | grep -q phoenix; then
    echo "  Phoenix already running."
  elif command -v docker &>/dev/null; then
    echo "  Starting Phoenix via docker-compose..."
    cd "$PROJECT_DIR"
    docker compose up -d
    echo "  Waiting for Phoenix to be ready..."
    for i in $(seq 1 30); do
      if curl -sf http://localhost:6006 >/dev/null 2>&1; then
        echo "  Phoenix ready at http://localhost:6006"
        break
      fi
      sleep 1
    done
  else
    echo "  WARNING: Docker not found. Phoenix tracing will not be available."
    echo "  You can still run evals without tracing."
  fi
fi

# ── Step 4: Check NVIDIA API key ────────────────────────────────
echo ""
echo "[4/5] Checking NVIDIA API key (for judge LLM)..."
if [ -n "${NVIDIA_API_KEY:-}" ]; then
  echo "  NVIDIA_API_KEY is set."
else
  echo "  WARNING: NVIDIA_API_KEY not set."
  echo "  The judge LLM needs this to score eval responses."
  echo "  Get a key at https://build.nvidia.com and run:"
  echo "    export NVIDIA_API_KEY=<your-key>"
fi

# ── Step 5: Verify sandbox connectivity ─────────────────────────
echo ""
echo "[5/5] Checking NemoClaw sandbox at $SANDBOX_URL ..."
HEALTH_URL="${SANDBOX_URL%/v1}/health"

if curl -sf "$HEALTH_URL" -H "Authorization: Bearer ${NEMOCLAW_API_KEY:-}" 2>/dev/null; then
  echo ""
  echo "  Sandbox is reachable and healthy."
else
  echo "  WARNING: Cannot reach sandbox at $HEALTH_URL"
  echo "  Make sure:"
  echo "    1. NemoClaw sandbox is running (nemoclaw <name> status)"
  echo "    2. Port 8642 is accessible"
  echo "    3. NEMOCLAW_API_KEY is set if auth is required"
  echo ""
  echo "  To extract the API key from a running sandbox:"
  echo "    openshell sandbox exec <name> -- printenv API_SERVER_KEY"
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
echo "=== Setup Summary ==="
echo "  Project dir:   $PROJECT_DIR"
echo "  Sandbox URL:   $SANDBOX_URL"
echo "  Phoenix:       ${SKIP_PHOENIX:+skipped}${SKIP_PHOENIX:-http://localhost:6006}"
echo "  NVIDIA API:    ${NVIDIA_API_KEY:+set}${NVIDIA_API_KEY:-NOT SET}"
echo "  Sandbox auth:  ${NEMOCLAW_API_KEY:+set}${NEMOCLAW_API_KEY:-NOT SET}"
echo ""
echo "Next steps:"
echo "  1. Run eval:    ./scripts/run-eval.sh"
echo "  2. Run observe: ./scripts/run-observe.sh"
echo "  3. View results: open http://localhost:6006"
