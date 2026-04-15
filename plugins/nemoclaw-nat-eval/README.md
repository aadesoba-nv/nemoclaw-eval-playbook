# nemoclaw-nat-eval

**NemoClaw + NVIDIA NeMo Agent Toolkit (NAT) — Telemetry, Evaluation & Profiling**

Adds NAT observability and structured evaluation capabilities to NemoClaw Hermes sandboxes. Mirrors the `hermes-brev` skill pattern but extends it with NAT `nat eval`, `nat run`, and Phoenix tracing integration.

## What This Skill Provides

| Capability | NAT Command | Description |
|------------|-------------|-------------|
| Single-prompt tracing | `nat run` | Send a prompt, view full trace in Phoenix |
| Dataset evaluation | `nat eval` | Score agent responses with Ragas metrics |
| Profiling | `nat eval` (profiler) | Latency, token efficiency, bottleneck analysis |
| Observability | Multiple backends | Phoenix, LangSmith, Langfuse, Weave, OTel |

## Quick Start

```bash
# 1. Deploy NemoClaw Hermes sandbox
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
nemoclaw onboard --agent hermes

# 2. Install NAT
pip install "nvidia-nat[eval,phoenix]"

# 3. Start Phoenix
docker run -d -p 6006:6006 -p 4317:4317 arizephoenix/phoenix:13.22

# 4. Set credentials
export NVIDIA_API_KEY=<from-build.nvidia.com>
export NEMOCLAW_API_KEY=$(openshell sandbox exec my-assistant -- printenv API_SERVER_KEY)

# 5. Observe
nat run --config_file references/observe-config.yml --input "Hello, what can you do?"

# 6. Evaluate
nat eval --config_file references/eval-config.yml
```

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Full skill guide (NemoClaw setup + NAT integration) |
| `references/eval-config.yml` | NAT eval config targeting Hermes sandbox |
| `references/observe-config.yml` | NAT observe config with Phoenix tracing |
| `references/sample-dataset.json` | 5-question starter eval dataset |
| `references/dataset-format.md` | Dataset schema and category guide |

## Requirements

- NemoClaw (alpha, latest) with Hermes agent
- Python 3.11-3.13
- Docker
- NVIDIA API Key (for judge LLM)

## Related Skills

- `hermes-brev` — Deploy Hermes on Brev cloud instances
- `openclaw-brev` — Deploy OpenClaw on Brev cloud instances
- `nemoclaw-user-get-started` — NemoClaw installation and first sandbox
- `nemoclaw-user-monitor-sandbox` — Sandbox health and log monitoring
