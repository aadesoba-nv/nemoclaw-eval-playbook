# Context: NemoClaw + NAT Telemetry & Evaluation Playbook

This file provides working context for building the NemoClaw + NAT telemetry integration. Use this as a reference when implementing any of the components.

---

## Project Goal

Build a playbook that enables partners to:
1. Deploy a NemoClaw-sandboxed AI agent
2. Instrument it with NAT telemetry for runtime observability
3. Run structured evaluations using NAT's eval framework
4. Iterate on agent quality using data-driven feedback

## Who Is This For

- **Primary audience:** Partners (SHI, WWT, HPE) doing NemoClaw enablement
- **Soft launch:** HPE A&PS hackathon in Madrid (~2026-04-21)
- **Leads:** Dave Barry, Adi Adesoba (proposed by Agerneh)
- **Context:** Adapting existing Agentic AI Deep Dive to add NemoClaw focus

## Key Repos

| Repo | Purpose | Language | Key Entry Points |
|------|---------|----------|------------------|
| [NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw) | Sandboxed agent deployment | TypeScript + Python | `bin/nemoclaw.js`, `agents/hermes/plugin/__init__.py` |
| [NVIDIA/NeMo-Agent-Toolkit](https://github.com/NVIDIA/NeMo-Agent-Toolkit) | Agent instrumentation, eval, profiling | Python | `nat run`, `nat eval`, `nat info` |
| [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) | Agent runtime (sandbox, gateway, policies) | — | Underlying NemoClaw infrastructure |

## Architecture Cheat Sheet

### NemoClaw Sandbox Stack

```
┌─────────────────────────────────────────┐
│  Host                                    │
│  ┌──────────────────────────────────┐   │
│  │ nemoclaw CLI                      │   │
│  │  • onboard (wizard)               │   │
│  │  • connect (shell into sandbox)   │   │
│  │  • status / logs                  │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ OpenShell Gateway                 │   │
│  │  • Credential store              │   │
│  │  • Inference proxy               │   │
│  │  • Policy engine                 │   │
│  │  • Device auth                   │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ Sandbox Container                 │   │
│  │  ┌────────────────────────────┐  │   │
│  │  │ Agent (Hermes or OpenClaw) │  │   │
│  │  │  • LLM calls → gateway    │  │   │
│  │  │  • Tools, memory, skills   │  │   │
│  │  │  • NemoClaw plugin         │  │   │
│  │  └────────────────────────────┘  │   │
│  │  Network: egress-controlled       │   │
│  │  Filesystem: /sandbox, /tmp only  │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### NAT Telemetry Stack

```
┌─────────────────────────────────────────┐
│  NAT Workflow                            │
│  ┌──────────────────────────────────┐   │
│  │ IntermediateStepManager           │   │
│  │  → publishes events to stream     │   │
│  └───────────┬──────────────────────┘   │
│              │                           │
│  ┌───────────▼──────────────────────┐   │
│  │ Telemetry Exporters (concurrent)  │   │
│  │  • Phoenix (local tracing UI)    │   │
│  │  • LangSmith                     │   │
│  │  • OpenTelemetry Collector       │   │
│  │  • File (local JSON/CSV)         │   │
│  │  • Langfuse, Weave, Dynatrace   │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ Evaluation Harness                │   │
│  │  • Ragas: accuracy, groundedness │   │
│  │  • Trajectory evaluator          │   │
│  │  • Custom evaluator plugins      │   │
│  │  • Dataset: JSON/JSONL/CSV       │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ Profiler                          │   │
│  │  • Token tracking per invocation │   │
│  │  • Latency analysis              │   │
│  │  • Gantt chart visualization     │   │
│  │  • Bottleneck scoring            │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

## Integration Points

### How the Sandbox Exposes APIs

| Agent | API Type | Port | Auth | Endpoint Pattern |
|-------|----------|------|------|-----------------|
| Hermes | OpenAI-compatible | 8642 | Bearer token (`API_SERVER_KEY`) | `http://localhost:8642/v1/chat/completions` |
| OpenClaw | Gateway API | 18789 | Device pairing | `http://localhost:18789/` |

### NemoClaw Plugin System (Hermes)

The Hermes plugin at `agents/hermes/plugin/__init__.py` provides:

```python
def register(ctx):
    # Register tools the agent can call
    ctx.register_tool(name="...", schema={...}, handler=func)

    # Register lifecycle hooks
    ctx.register_hook("on_session_start", callback)

    # Inject system messages
    ctx.inject_message(text, role="system")
```

This is the primary extension point for adding in-sandbox instrumentation.

### NAT Workflow Configuration (YAML-driven)

```yaml
# Core pattern: everything is configured in YAML
llms:
  my_llm:
    _type: nim
    model_name: nvidia/nemotron-3-nano-30b-a3b
    base_url: http://localhost:8642/v1  # Point at NemoClaw sandbox

general:
  telemetry:
    tracing:
      phoenix:
        _type: phoenix
        endpoint: http://localhost:6006/v1/traces

eval:
  general:
    output_dir: ./results/
    dataset:
      _type: json
      file_path: ./eval-data.json
  evaluators:
    accuracy:
      _type: ragas
      metric: AnswerAccuracy
      llm_name: judge_llm

workflow:
  _type: react_agent
  llm_name: my_llm
```

### NAT Middleware System

Middleware wraps function calls with pre/post hooks. Configured in YAML:

```yaml
middleware:
  telemetry_logger:
    _type: logging_middleware
    log_level: DEBUG
    register_llms: true  # Auto-wrap all LLM calls
    register_workflow_functions: true  # Auto-wrap all workflow functions

functions:
  my_func:
    _type: my_function
    middleware: ["telemetry_logger"]
```

Custom middleware extends `DynamicFunctionMiddleware`:
- `pre_invoke(context)` — inspect/modify inputs before function runs
- `post_invoke(context)` — process/transform outputs after function runs

## Three Integration Layers

### Layer 1: Inference Telemetry (Gateway-Level)

- **Scope:** Every LLM call from any agent
- **Data:** Tokens, latency, model, provider, prompt/completion content
- **Approach:** Tap OpenShell gateway logs or add proxy sidecar
- **Complexity:** Low
- **Agent support:** OpenClaw + Hermes

### Layer 2: External Evaluation Harness

- **Scope:** Structured quality assessment
- **Data:** Accuracy, trajectory quality, groundedness, safety
- **Approach:** NAT `nat eval` targeting sandbox API as remote endpoint
- **Complexity:** Medium
- **Agent support:** OpenClaw + Hermes (Hermes easier due to auth)

### Layer 3: In-Sandbox NAT Instrumentation (Hermes Only)

- **Scope:** Deep agent behavior tracing
- **Data:** Reasoning steps, tool selection, memory access, skill chains
- **Approach:** Extend NemoClaw Hermes plugin to inject NAT callbacks
- **Complexity:** High
- **Agent support:** Hermes only (Python)

## Implementation Priorities

### For Hackathon MVP (Layer 2 focus)

1. **Create eval dataset** — 20-30 questions across: general knowledge, tool use, multi-step reasoning, policy compliance, safety
2. **Build NAT eval config** — YAML targeting Hermes sandbox API at `localhost:8642/v1`
3. **Package Phoenix** — `docker-compose.yml` for local tracing dashboard
4. **Write helper scripts:**
   - `setup-eval.sh` — install NAT, start Phoenix, verify sandbox connectivity
   - `run-eval.sh` — execute `nat eval` with pre-built config
   - `view-results.sh` — open Phoenix dashboard, summarize scores
5. **Write participant playbook** — step-by-step guide with screenshots
6. **Test on DGX** — verify with remote NemoClaw deploy

### Eval Dataset Template

```json
[
  {
    "id": "unique-id",
    "category": "general_knowledge|tool_use|multi_step|policy_compliance|safety",
    "question": "The prompt to send to the agent",
    "answer": "Expected answer or behavior description",
    "eval_type": "accuracy|trajectory|safety",
    "metadata": {
      "difficulty": "easy|medium|hard",
      "requires_tools": false,
      "expected_behavior": "optional description"
    }
  }
]
```

### NAT Eval Config Template

```yaml
# nemoclaw-eval.yml
llms:
  # The NemoClaw sandbox as a "model"
  nemoclaw_agent:
    _type: nim
    model_name: hermes
    base_url: http://localhost:8642/v1
    temperature: 0.0
    max_tokens: 2048

  # Judge LLM for evaluation scoring
  judge_llm:
    _type: nim
    model_name: nvidia/llama-3.3-nemotron-super-49b-v1
    max_tokens: 1024

general:
  telemetry:
    logging:
      console:
        _type: console
        level: INFO
      file:
        _type: file
        path: ./eval-logs/telemetry.log
        level: DEBUG
    tracing:
      phoenix:
        _type: phoenix
        endpoint: http://localhost:6006/v1/traces
        project: nemoclaw-eval

eval:
  general:
    output_dir: ./eval-results/
    max_concurrency: 1
    dataset:
      _type: json
      file_path: ./eval-datasets/nemoclaw-tasks.json
    profiler:
      enabled: true
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
      llm_name: judge_llm

workflow:
  _type: react_agent
  llm_name: nemoclaw_agent
  tool_names: []
  verbose: true
```

## Critical Nuances

### Sandbox Network Policy

For telemetry export from inside the sandbox, add to policy:
```yaml
- host: "host.docker.internal"
  port: 4317
  protocol: tcp
  reason: "OpenTelemetry collector"
- host: "host.docker.internal"
  port: 6006
  protocol: tcp
  reason: "Phoenix tracing UI"
```

For external eval (Layer 2), no policy changes needed — NAT runs on the host.

### Auth Token Extraction

Hermes uses `API_SERVER_KEY` environment variable. To extract for eval:
```bash
# From inside sandbox
nemoclaw <name> connect
echo $API_SERVER_KEY

# Or from host
openshell sandbox exec <name> -- printenv API_SERVER_KEY
```

Then set in NAT config or env:
```bash
export NEMOCLAW_API_KEY=<token>
```

### NemoClaw Agent ≠ Bare LLM

The sandbox agent includes reasoning loops, tool calls, memory, and policies. When NAT eval sends a prompt, the response comes from the full agent pipeline, not just an LLM. This means:

- Responses may be longer and more structured than bare LLM output
- Latency includes agent overhead (tool calls, memory lookups)
- Some prompts may trigger tool use that fails due to sandbox restrictions
- Eval metrics should account for this (e.g., trajectory eval is more meaningful than pure accuracy)

### File Structure for the Playbook

```
nemoclaw-nat-playbook/
├── README.md                    # Step-by-step participant guide
├── eval-configs/
│   ├── nemoclaw-eval.yml        # NAT eval config
│   └── nemoclaw-observe.yml     # NAT observability config
├── eval-datasets/
│   ├── general-knowledge.json
│   ├── tool-use.json
│   ├── policy-compliance.json
│   └── safety.json
├── scripts/
│   ├── setup-eval.sh            # Install NAT + Phoenix
│   ├── run-eval.sh              # Execute evaluation
│   └── view-results.sh          # Open dashboard + summarize
├── docker-compose.yml           # Phoenix + OTel collector
├── nemoclaw-nat-telemetry-spec.md
└── nemoclaw-nat-telemetry-context.md
```

## Dependencies

| Component | Version | Install |
|-----------|---------|---------|
| NemoClaw | alpha (latest) | `curl -fsSL https://www.nvidia.com/nemoclaw.sh \| bash` |
| NAT | latest stable | `pip install "nvidia-nat[eval,phoenix]"` |
| Phoenix | 13.x+ | `docker run arizephoenix/phoenix:13.22` |
| Python | 3.11-3.13 | Required for NAT |
| Node.js | 22.16+ | Required for NemoClaw |
| Docker | latest | Required for both |
| NVIDIA API Key | — | From build.nvidia.com |

## Related Specs & Docs

- [Spec document](./nemoclaw-nat-telemetry-spec.md) — full spec with phases, risks, success metrics
- [NemoClaw docs](https://docs.nvidia.com/nemoclaw/latest/) — official documentation
- [NAT docs](https://docs.nvidia.com/nemo/agent-toolkit/latest/) — official documentation
- [NAT eval guide](https://docs.nvidia.com/nemo/agent-toolkit/latest/improve-workflows/evaluate.html)
- [NAT observability guide](https://docs.nvidia.com/nemo/agent-toolkit/latest/run-workflows/observe/observe.html)
- [NAT middleware guide](https://docs.nvidia.com/nemo/agent-toolkit/latest/build-workflows/advanced/middleware.html)
