# NemoClaw + NAT Skill Guide

**How to instrument NemoClaw agents with NVIDIA NeMo Agent Toolkit telemetry and evaluation — ready to share with your team.**

This guide distills what works from building the NemoClaw + NAT integration. It covers `nat eval`, `nat run`, and the `nat` CLI against a NemoClaw Hermes sandbox. Copy-paste ready.

---

## The Pattern in 30 Seconds

NAT is a Python toolkit for agent telemetry, evaluation, and profiling. NemoClaw runs agents in sandboxed containers with an OpenAI-compatible API. The integration:

1. NAT treats the NemoClaw sandbox API as an LLM endpoint (`base_url`)
2. `nat eval` sends dataset prompts to the agent, scores responses with a judge LLM
3. `nat run` sends single prompts with tracing to a Phoenix dashboard
4. No modifications to NemoClaw — NAT runs entirely on the host

---

## Part A: Setting Up NemoClaw (Hermes Agent)

### Install NemoClaw

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
source ~/.bashrc
```

Requires: Docker running, Node.js 22.16+ (installer handles this), 4+ vCPU / 8 GB RAM / 20 GB disk.

### Onboard Hermes

```bash
# Interactive (wizard guides you through provider + policy selection)
nemoclaw onboard --agent hermes

# Non-interactive (scripted)
export NVIDIA_API_KEY=<key-from-build.nvidia.com>
nemoclaw onboard --agent hermes --non-interactive --yes-i-accept-third-party-software
```

The wizard asks for:
- **Inference provider** — NVIDIA Endpoints (recommended), OpenAI, Anthropic, Gemini, local Ollama, or any OpenAI-compatible endpoint
- **Policy tier** — Restricted, Balanced (default), or Open
- **Sandbox name** — lowercase alphanumeric + hyphens (e.g., `my-assistant`)

### Verify

```bash
nemoclaw my-assistant status     # Health, model, provider
nemoclaw my-assistant logs       # Recent logs
nemoclaw my-assistant connect    # Shell into sandbox
```

### Key Details

| Fact | Value |
|------|-------|
| Hermes API | `http://localhost:8642/v1/chat/completions` |
| Auth | Bearer token via `API_SERVER_KEY` env var inside sandbox |
| Protocol | OpenAI-compatible chat completions |
| Agent tools | `nemoclaw_status`, `nemoclaw_info`, `nemoclaw_reload_skills` |

### Extract the sandbox auth token

```bash
# From host (preferred)
openshell sandbox exec my-assistant -- printenv API_SERVER_KEY

# Or connect and echo it
nemoclaw my-assistant connect
echo $API_SERVER_KEY
```

### NemoClaw CLI Cheat Sheet

```bash
nemoclaw onboard --agent hermes          # Setup wizard
nemoclaw <name> status                   # Health check
nemoclaw <name> connect                  # Shell into sandbox
nemoclaw <name> logs --follow            # Stream logs
nemoclaw <name> destroy                  # Delete sandbox
nemoclaw <name> policy-add               # Add network preset
nemoclaw <name> policy-list              # List policies
nemoclaw <name> skill install <dir>      # Deploy a skill
nemoclaw list                            # List all sandboxes
nemoclaw debug                           # Diagnostics tarball
openshell term                           # Live TUI network monitor
```

---

## Part B: Installing NAT

```bash
# Core + eval + Phoenix tracing
pip install "nvidia-nat[eval,phoenix]"

# Verify
nat --help
nat info components -t evaluator    # List available evaluators
nat info components -t tracing      # List tracing exporters
```

Requires: Python 3.11-3.13.

---

## Part C: NAT Capabilities with NemoClaw

### C.1 `nat run` — Single prompt with telemetry

Send one prompt to the NemoClaw agent and capture a trace in Phoenix.

**Config (`nemoclaw-observe.yml`):**

```yaml
llms:
  nemoclaw_agent:
    _type: nim
    model_name: hermes
    base_url: ${NEMOCLAW_SANDBOX_URL:-http://localhost:8642/v1}
    api_key: ${NEMOCLAW_API_KEY:-no-key-set}
    temperature: 0.0
    max_tokens: 2048
    chat_template_kwargs:
      enable_thinking: false

workflow:
  _type: chat_completion
  llm_name: nemoclaw_agent

general:
  telemetry:
    logging:
      console:
        _type: console
        level: INFO
    tracing:
      phoenix:
        _type: phoenix
        endpoint: http://localhost:6006/v1/traces
        project: nemoclaw-observe
```

**Run it:**

```bash
# Start Phoenix first
docker run -d --name phoenix -p 6006:6006 -p 4317:4317 arizephoenix/phoenix:13.22

# Set env vars
export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1
export NEMOCLAW_API_KEY=<your-api-server-key>

# Send a prompt
nat run --config_file nemoclaw-observe.yml \
    --input "What security controls does this sandbox have?"

# View trace at http://localhost:6006
```

**Why `chat_completion` instead of `react_agent`?**
The NemoClaw Hermes agent already has its own agent loop with tools. `chat_completion` is a simple passthrough — sends the prompt, returns the response. Using `react_agent` would create a double-agent-loop, and NAT 1.5+ requires `react_agent` to have at least one tool defined.

### C.2 `nat eval` — Dataset-driven evaluation with scoring

Run a curated set of prompts, score responses with a judge LLM, and generate profiling data.

**Config (`nemoclaw-eval.yml`):**

```yaml
llms:
  nemoclaw_agent:
    _type: nim
    model_name: hermes
    base_url: ${NEMOCLAW_SANDBOX_URL:-http://localhost:8642/v1}
    api_key: ${NEMOCLAW_API_KEY:-no-key-set}
    temperature: 0.0
    max_tokens: 2048
    chat_template_kwargs:
      enable_thinking: false

  judge_llm:
    _type: nim
    model_name: meta/llama-3.3-70b-instruct
    max_tokens: 8
    chat_template_kwargs:
      enable_thinking: false

  trajectory_judge:
    _type: nim
    model_name: meta/llama-3.3-70b-instruct
    temperature: 0.0
    max_tokens: 1024
    chat_template_kwargs:
      enable_thinking: false

workflow:
  _type: chat_completion
  llm_name: nemoclaw_agent

eval:
  general:
    max_concurrency: 1
    output:
      dir: ./eval-results/
    dataset:
      _type: json
      file_path: eval-datasets/combined.json
    profiler:
      workflow_runtime_forecast: true
      compute_llm_metrics: true
      bottleneck_analysis:
        enable_nested_stack: true

  evaluators:
    accuracy:
      _type: ragas
      metric: AnswerAccuracy
      llm_name: judge_llm
    groundedness:
      _type: ragas
      metric: ResponseGroundedness
      llm_name: judge_llm
    trajectory:
      _type: trajectory
      llm_name: trajectory_judge
```

**Dataset format (JSON):**

```json
[
  {
    "id": "gen-001",
    "question": "What are three security benefits of running AI agents in sandboxed containers?",
    "answer": "Process isolation, network policy enforcement, and filesystem restrictions."
  }
]
```

**Run it:**

```bash
export NVIDIA_API_KEY=<your-key>
export NEMOCLAW_API_KEY=<sandbox-key>

nat eval --config_file nemoclaw-eval.yml
```

**Output in `eval-results/`:**

| File | Contents |
|------|----------|
| `workflow_output.json` | Every question + agent response |
| `accuracy_output.json` | Ragas AnswerAccuracy scores (0-1) |
| `groundedness_output.json` | Ragas ResponseGroundedness scores |
| `trajectory_output.json` | Trajectory quality scores |
| `standardized_data_all.csv` | Profiler: latency, tokens, model |
| `workflow_profiling_report.txt` | Human-readable performance summary |
| `gantt_chart.png` | Timeline visualization |

### C.3 `nat info` — Discover available components

```bash
# What evaluators can I use?
nat info components -t evaluator

# What tracing backends are available?
nat info components -t tracing

# What logging options exist?
nat info components -t logging

# What middleware is built in?
nat info components -t middleware
```

### C.4 `nat eval` CLI overrides

Override any config value from the command line:

```bash
# Change concurrency
nat eval --config_file nemoclaw-eval.yml --override eval.general.max_concurrency 2

# Change the model
nat eval --config_file nemoclaw-eval.yml --override llms.nemoclaw_agent.model_name "different-model"

# Use a different dataset
nat eval --config_file nemoclaw-eval.yml --override eval.general.dataset.file_path "eval-datasets/safety.json"

# Change the sandbox URL
nat eval --config_file nemoclaw-eval.yml --override llms.nemoclaw_agent.base_url "http://remote-dgx:8642/v1"
```

---

## Part D: Available Evaluators

NAT provides these evaluator types out of the box:

| Evaluator | `_type` | What It Scores | judge LLM Tokens |
|-----------|---------|---------------|-----------------|
| Answer Accuracy | `ragas` + `AnswerAccuracy` | Response correctness vs ground truth | 8 |
| Response Groundedness | `ragas` + `ResponseGroundedness` | Whether response is grounded in context | 8 |
| Context Relevance | `ragas` + `ContextRelevance` | Whether retrieved context is relevant | 8 |
| Trajectory | `trajectory` | Quality of agent reasoning path | 1024 |
| Custom | Plugin system | Your own scoring logic | Varies |

**Best judge LLMs** (Ragas leaderboard):
1. `meta/llama-3.3-70b-instruct`
2. `mistralai/mixtral-8x22b-instruct-v0.1`
3. `meta/llama-3.1-70b-instruct`

---

## Part E: Tracing Backends

NAT supports these telemetry exporters concurrently:

| Backend | `_type` | Setup |
|---------|---------|-------|
| Phoenix | `phoenix` | `docker run arizephoenix/phoenix:13.22` |
| LangSmith | `langsmith` | Set `LANGSMITH_API_KEY` |
| Langfuse | `langfuse` | Self-hosted or cloud |
| W&B Weave | `weave` | Set `WANDB_API_KEY` |
| Dynatrace | `dynatrace` | Enterprise |
| OTel Collector | `otel` | Any OTel-compatible backend |
| File | `file` | Local JSON, no setup |

**Multiple exporters run simultaneously:**

```yaml
general:
  telemetry:
    tracing:
      phoenix:
        _type: phoenix
        endpoint: http://localhost:6006/v1/traces
      file_backup:
        _type: file
        path: ./traces.json
```

---

## Part F: Profiler Metrics

When `eval.general.profiler` is enabled, NAT automatically collects:

- **Latency** — per-request and aggregated (P50/P95/P99)
- **Token efficiency** — input/output tokens per request
- **Bottleneck analysis** — identifies slowest operations in the call stack
- **Concurrency spikes** — detects periods of high parallel load
- **Gantt chart** — visual timeline of operations
- **Inference optimization signals** — caching opportunities, prompt prefix analysis

---

## Part G: Gotchas & Tips

### The sandbox is a full agent, not a bare LLM

When NAT sends a prompt to the Hermes API, the response includes the agent's full reasoning — tool calls, memory lookups, skill invocations. Eval metrics reflect the entire agent pipeline, not just the model.

### Concurrency = 1 for single sandbox

A NemoClaw sandbox is a single agent instance. Set `max_concurrency: 1` to avoid overwhelming it. For parallel eval, deploy multiple sandboxes.

### Auth token management

The `API_SERVER_KEY` is the Hermes bearer token inside the sandbox. Extract it with `openshell sandbox exec <name> -- printenv API_SERVER_KEY`. It does not change unless the sandbox is recreated.

### NAT env vars vs sandbox env vars

| Variable | Where | Purpose |
|----------|-------|---------|
| `NVIDIA_API_KEY` | Host (NAT) | Judge LLM on NVIDIA endpoints |
| `NEMOCLAW_API_KEY` | Host (NAT) | Authenticates to sandbox Hermes API |
| `API_SERVER_KEY` | Inside sandbox | Same key, different name |
| `NEMOCLAW_SANDBOX_URL` | Host (NAT) | Sandbox API endpoint |

### Remote sandbox via SSH tunnel

```bash
ssh -L 8642:localhost:8642 user@dgx-ip
export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1
```

### Rate limiting

25 eval questions x 3 evaluators = 75+ judge LLM calls. At `max_concurrency: 1` this is slow but safe. If you hit 429 errors, reduce the dataset or deploy NIM locally.

---

## Part G.5: Running End-to-End on NVIDIA Brev

[NVIDIA Brev](https://brev.nvidia.com) gives you on-demand GPU instances with Docker pre-installed. A CPU-only instance is sufficient (~$0.10/hr) since inference goes to NVIDIA Endpoints.

### Setup (local machine)

```bash
# Install Brev CLI
brew install brevdev/homebrew-brev/brev   # macOS
# Or Linux: curl -fsSL https://raw.githubusercontent.com/brevdev/brev-cli/main/bin/install-latest.sh | bash

brev login
brev create nemoclaw-eval --min-vcpu 4 --min-ram 16 --min-disk 50
brev shell nemoclaw-eval
```

### Install everything (on the Brev instance)

```bash
# NemoClaw
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash && source ~/.bashrc
export NVIDIA_API_KEY=<your-key>
nemoclaw onboard --agent hermes --non-interactive --yes-i-accept-third-party-software

# NAT + Phoenix
pip install "nvidia-nat[eval,phoenix]"
docker run -d --name phoenix -p 6006:6006 -p 4317:4317 arizephoenix/phoenix:13.22
```

### Run the playbook (on the Brev instance)

```bash
git clone <your-repo-url> claw-use-cases && cd claw-use-cases

export NEMOCLAW_API_KEY=$(openshell sandbox exec my-assistant -- printenv API_SERVER_KEY)
export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1

# Smoke test
nat run --config_file eval-configs/nemoclaw-observe.yml \
    --input "What security controls does this sandbox have?"

# Full eval
./scripts/run-eval.sh --with-phoenix
```

### View Phoenix locally

```bash
# Second local terminal
brev port-forward nemoclaw-eval --port 6006:6006
# Open http://localhost:6006
```

### Pull results and clean up

```bash
# Local machine
scp -r ubuntu@nemoclaw-eval:~/claw-use-cases/eval-results ./eval-results-brev

# Tear down
brev delete nemoclaw-eval
```

### Brev gotchas

- **IP changes on restart** — `brev refresh` updates SSH config
- **Capacity risk** — stopping releases GPU; restart may fail. Git push first.
- **Cost** — CPU ~$0.10/hr. Don't leave running overnight.
- **GPU instance** — only if you want local Ollama: `brev create nemoclaw-eval --gpu-name L4`
- **`nemoclaw deploy`** — deprecated. Use manual provision (above).

---

## Part H: What's Next (Phase 2+)

These are not built yet but are the logical next steps:

1. **Layer 1: Inference sidecar** — tap OpenShell gateway logs for LLM-call-level telemetry (agent-agnostic)
2. **Layer 3: In-sandbox NAT** — extend the NemoClaw Hermes plugin to inject NAT callbacks directly into the agent process
3. **Custom evaluators** — NemoClaw-specific metrics (policy compliance scoring, tool success rate)
4. **CI pipeline** — run evals on every NemoClaw release to catch regressions
5. **Eval leaderboard** — compare agents, models, and configs across eval runs
