# NemoClaw + NAT Telemetry & Evaluation Playbook

Instrument NemoClaw-sandboxed AI agents with NVIDIA NeMo Agent Toolkit (NAT) telemetry and run structured evaluations to measure agent quality.

> **NemoClaw gets your agent running. NAT tells you if it's running well.**

## Why This Matters

You can deploy an agent in 5 minutes with NemoClaw. But how do you know if it's actually good? This playbook gives you the answer — quantitative, repeatable, and visual.

- **Go from "it works" to "it scores 0.85 on accuracy"** — Without eval, you're guessing. With NAT, you get real numbers: does the agent answer correctly? Is it grounded in facts? Does it follow a coherent reasoning path? You can compare models, configs, and policy tiers with data instead of vibes.

- **Zero sandbox modification** — NAT runs entirely on the host. You don't touch the agent, don't modify the Dockerfile, don't install anything inside the sandbox. Point NAT at the API, run one command, get a full report. This matters because production sandboxes should be immutable — you evaluate them as-is.

- **See what your agent is actually doing** — Phoenix traces show every request/response with latency breakdowns and token usage. When something's slow or wrong, you can see exactly where. This is the difference between "my agent is slow" and "the agent spends 4 seconds on tool calls before responding."

For hackathon participants: showing eval scores and traces in your demo is a stronger story than a chat window. It's the difference between a prototype and something you'd put in front of a customer.

## What This Does

1. Points NAT's evaluation framework at a running NemoClaw sandbox
2. Sends a curated dataset of prompts to the agent
3. Scores responses using Ragas metrics (accuracy, groundedness) and trajectory evaluation
4. Captures full telemetry traces viewable in a Phoenix dashboard

The NemoClaw agent is treated as a black-box behind its OpenAI-compatible API. NAT runs on the host — no sandbox modifications needed.

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| NemoClaw sandbox | alpha (latest) | Running with Hermes agent |
| Python | 3.11 - 3.13 | For NAT |
| Docker | latest | For Phoenix tracing dashboard + NemoClaw sandbox |
| Node.js | 22.16+ | For NemoClaw CLI |
| NVIDIA API Key | — | From [build.nvidia.com](https://build.nvidia.com) (for judge LLM + inference) |
| pip / uv | latest | Python package manager |

### Hardware

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 vCPU | 4+ vCPU |
| RAM | 8 GB | 16 GB |
| Disk | 20 GB free | 40 GB free |

---

## Part 0: Setting Up NemoClaw with Hermes

Before running evaluations, you need a running NemoClaw sandbox. This section walks through installing NemoClaw, onboarding the Hermes agent, and verifying it works.

> Skip this section if you already have a running NemoClaw sandbox.

### What is NemoClaw?

NemoClaw is NVIDIA's open-source reference stack for running AI agents safely in sandboxed containers. It provides:
- **Sandbox isolation** — agents run in Docker containers with network policies, filesystem restrictions, and process limits
- **Inference routing** — all LLM calls go through a host-side gateway that holds credentials (the agent never sees API keys)
- **Guided onboarding** — a wizard sets up the sandbox, configures inference providers, and applies security policies
- **Multi-agent support** — supports OpenClaw (Node.js) and Hermes (Python) agents

### What is Hermes?

Hermes is a Python-based self-improving AI agent from Nous Research. NemoClaw runs it inside an OpenShell sandbox with:
- An OpenAI-compatible API on port 8642 (`/v1/chat/completions`)
- Bearer token auth (`API_SERVER_KEY` env var)
- Built-in tools, memory, skills, and a learning loop
- NemoClaw plugin providing `nemoclaw_status`, `nemoclaw_info`, and `nemoclaw_reload_skills` tools

This playbook targets Hermes because it's Python-based (aligning with NAT) and exposes a clean OpenAI-compatible API for external evaluation.

### Step 0.1: Install NemoClaw

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
```

This installs Node.js (if needed) and the `nemoclaw` CLI. If `nemoclaw` is not found after install, reload your shell:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

### Step 0.2: Onboard with Hermes agent

Run the onboard wizard with the `--agent hermes` flag:

```bash
nemoclaw onboard --agent hermes
```

The wizard will prompt you to:

1. **Choose an inference provider** — select one:

   | Provider | Key Required | Notes |
   |----------|-------------|-------|
   | NVIDIA Endpoints | `NVIDIA_API_KEY` | Recommended. Hosted models on build.nvidia.com |
   | OpenAI | `OPENAI_API_KEY` | GPT-5.4 family |
   | Anthropic | `ANTHROPIC_API_KEY` | Claude Opus/Sonnet/Haiku |
   | Google Gemini | `GEMINI_API_KEY` | Gemini Pro/Flash |
   | Local Ollama | None | Runs locally, no GPU needed for small models |
   | Other OpenAI-compatible | Custom URL + key | Any `/v1/chat/completions` endpoint |

2. **Select a policy tier** — controls sandbox network permissions:

   | Tier | Description |
   |------|-------------|
   | Restricted | No third-party access beyond inference |
   | Balanced (default) | Dev tooling, web search, package installs |
   | Open | Broad access including messaging platforms |

3. **Name your sandbox** — e.g., `my-assistant` (lowercase, alphanumeric + hyphens)

When complete, you'll see:

```
──────────────────────────────────────────────────
Sandbox      my-assistant (Landlock + seccomp + netns)
Model        nvidia/nemotron-3-super-120b-a12b (NVIDIA Endpoints)
──────────────────────────────────────────────────
Run:         nemoclaw my-assistant connect
Status:      nemoclaw my-assistant status
Logs:        nemoclaw my-assistant logs --follow
──────────────────────────────────────────────────
```

#### Non-interactive onboarding (for scripted setups)

```bash
export NVIDIA_API_KEY=<your-key>
nemoclaw onboard --agent hermes --non-interactive --yes-i-accept-third-party-software
```

### Step 0.3: Verify the sandbox is running

```bash
# Check sandbox status
nemoclaw my-assistant status

# View logs
nemoclaw my-assistant logs --follow
```

### Step 0.4: Chat with the agent

Connect to the sandbox shell:

```bash
nemoclaw my-assistant connect
```

Inside the sandbox, test the agent:

```bash
# Hermes exposes an OpenAI-compatible API — test it directly
curl -s http://localhost:8642/v1/chat/completions \
  -H "Authorization: Bearer $API_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes",
    "messages": [{"role": "user", "content": "Hello, what can you do?"}]
  }' | python3 -m json.tool
```

### Step 0.5: Extract the API key for NAT

While connected to the sandbox, grab the auth token:

```bash
echo $API_SERVER_KEY
```

Or from the host:

```bash
openshell sandbox exec my-assistant -- printenv API_SERVER_KEY
```

Save it for the eval steps below.

### NemoClaw CLI Reference

| Command | What It Does |
|---------|-------------|
| `nemoclaw onboard --agent hermes` | Run setup wizard for Hermes agent |
| `nemoclaw <name> status` | Show sandbox health, model, provider |
| `nemoclaw <name> connect` | Shell into the sandbox |
| `nemoclaw <name> logs [--follow]` | View sandbox logs |
| `nemoclaw <name> destroy` | Delete sandbox (warning: data loss) |
| `nemoclaw <name> policy-add` | Add network policy preset |
| `nemoclaw <name> policy-list` | List applied/available policy presets |
| `nemoclaw <name> skill install <path>` | Deploy a skill to the sandbox |
| `nemoclaw list` | List all sandboxes |
| `nemoclaw debug` | Collect diagnostics for bug reports |
| `nemoclaw credentials list` | List stored credentials |
| `nemoclaw credentials reset <KEY>` | Remove a stored credential |
| `nemoclaw uninstall` | Remove everything |
| `openshell term` | Open TUI for live network monitoring |

### Supported Platforms

| OS | Container Runtime | Status |
|----|-------------------|--------|
| Linux | Docker | Tested (primary) |
| macOS (Apple Silicon) | Colima, Docker Desktop | Tested with limitations |
| DGX Spark | Docker | Tested |
| Windows WSL2 | Docker Desktop (WSL backend) | Tested with limitations |

### Remote Deployment (SSH)

To run the sandbox on a remote GPU machine (e.g., DGX):

```bash
# SSH to the remote machine
ssh user@dgx-ip

# Install and onboard there
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
nemoclaw onboard --agent hermes

# From your local machine, SSH tunnel the ports
ssh -L 8642:localhost:8642 -L 6006:localhost:6006 user@dgx-ip
```

Then use `NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1` in the eval configs.

### End-to-End on NVIDIA Brev

[NVIDIA Brev](https://brev.nvidia.com) provides on-demand GPU instances across cloud providers with Docker, NVIDIA drivers, and SSH pre-configured. This is the fastest way to run the full playbook without provisioning your own hardware.

> For this playbook, a **CPU-only** instance is sufficient (~$0.10/hr) since inference goes to NVIDIA Endpoints. Only use a GPU instance if you want local inference via Ollama.

#### Brev Step 1: Install and authenticate the Brev CLI

```bash
# macOS
brew install brevdev/homebrew-brev/brev

# Linux
curl -fsSL https://raw.githubusercontent.com/brevdev/brev-cli/main/bin/install-latest.sh | bash

# Login (opens browser for SSO)
brev login
```

#### Brev Step 2: Create an instance

```bash
# CPU-only (cheapest — inference uses NVIDIA Endpoints)
brev create nemoclaw-eval --min-vcpu 4 --min-ram 16 --min-disk 50

# OR with GPU (if you want local Ollama inference)
brev create nemoclaw-eval --gpu-name L4
```

#### Brev Step 3: SSH in and install everything

```bash
brev shell nemoclaw-eval
```

On the instance:

```bash
# Install NemoClaw
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
source ~/.bashrc

# Set API key and onboard Hermes
export NVIDIA_API_KEY=<your-key-from-build.nvidia.com>
nemoclaw onboard --agent hermes --non-interactive --yes-i-accept-third-party-software

# Verify sandbox is running
nemoclaw my-assistant status

# Install NAT
pip install "nvidia-nat[eval,phoenix]"

# Start Phoenix
docker run -d --name phoenix -p 6006:6006 -p 4317:4317 arizephoenix/phoenix:13.22
```

#### Brev Step 4: Get the playbook onto the instance

```bash
# Option A: Clone from git
git clone <your-repo-url> claw-use-cases && cd claw-use-cases

# Option B: From a second LOCAL terminal, scp it up
scp -r ./claw-use-cases ubuntu@nemoclaw-eval:~/
# Then on the instance: cd ~/claw-use-cases
```

#### Brev Step 5: Set env vars and run

```bash
cd ~/claw-use-cases

# Env vars
export NVIDIA_API_KEY=<your-key>
export NEMOCLAW_API_KEY=$(openshell sandbox exec my-assistant -- printenv API_SERVER_KEY)
export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1

# Quick smoke test (single prompt + trace)
nat run --config_file eval-configs/nemoclaw-observe.yml \
    --input "What security controls does this sandbox have?"

# Full evaluation
./scripts/run-eval.sh --with-phoenix
```

#### Brev Step 6: View results locally

Open a **second local terminal** and forward Phoenix:

```bash
brev port-forward nemoclaw-eval --port 6006:6006
```

Then open http://localhost:6006 in your browser.

To pull results locally:

```bash
scp -r ubuntu@nemoclaw-eval:~/claw-use-cases/eval-results ./eval-results-brev
```

#### Brev Step 7: Tear down

```bash
# Stop (keeps data, stops compute billing)
brev stop nemoclaw-eval

# Delete entirely
brev delete nemoclaw-eval
```

#### Brev Gotchas

| Issue | Detail |
|-------|--------|
| IP changes on restart | Run `brev refresh` after restarting a stopped instance to update SSH config |
| Capacity risk | Stopping releases the GPU. Restart may fail if no capacity. Push results to git first. |
| Cost | CPU instances ~$0.10/hr. Don't leave running overnight. |
| `nemoclaw deploy` | Deprecated. Use manual provision + install (above) instead. |
| Python version | Brev instances ship Python — verify it's 3.11+ with `python3 --version` |

---

## Part 1: NAT Evaluation Quick Start (5 minutes)

### Step 1.0: Install NAT in a virtual environment

```bash
# Create venv (required on Ubuntu 24.04+ due to PEP 668)
sudo apt install python3.12-venv -y   # if needed
python3 -m venv ~/nat-venv
source ~/nat-venv/bin/activate

# Install NAT with all extras (use uv for reliable version resolution)
pip install uv
uv pip install "nvidia-nat[eval,phoenix,langchain]~=1.5.0"
uv pip install matplotlib   # for profiler Gantt charts

# Verify
nat --version   # should show 1.5.0
```

> **Important:** Always `source ~/nat-venv/bin/activate` before running NAT commands.

### Step 1.0.1: Set up the SSH tunnel for port 8642

The Hermes API runs inside a nested sandbox (Docker → k3s → pod → OpenShell sandbox). An SSH tunnel is required to make it accessible from the host:

```bash
# One-time: generate SSH config entry
openshell sandbox ssh-config my-assistant --gateway nemoclaw >> ~/.ssh/config

# Start the tunnel (keep running, or use -fN for background)
ssh -fN -L 8642:localhost:8642 openshell-my-assistant

# Verify
curl -s http://localhost:8642/health
# Expected: {"status": "ok", "platform": "hermes-agent"}
```

See [troubleshooting.md](troubleshooting.md) for details on why this is needed and what doesn't work.

### Step 1.1: Set environment variables

```bash
# NVIDIA API key for the judge LLM that scores eval responses
export NVIDIA_API_KEY=<your-key-from-build.nvidia.com>

# NemoClaw sandbox auth (extract from running sandbox)
# Option A: If you can access the sandbox directly
eval $(./scripts/extract-sandbox-auth.sh my-assistant)

# Option B: Set manually
export NEMOCLAW_SANDBOX_URL=http://localhost:8642/v1
export NEMOCLAW_API_KEY=<your-sandbox-api-server-key>
```

### Step 1.2: Run setup

```bash
mkdir -p observe-results   # required for nat run
./scripts/setup-eval.sh
```

This installs NAT, starts Phoenix, and verifies sandbox connectivity.

### Step 1.3: Run a quick observation

Send a single prompt and view the trace in Phoenix:

```bash
./scripts/run-observe.sh "What security controls does this sandbox have?"
```

Open http://localhost:6006 to see the trace.

### Step 1.4: Run the full evaluation

```bash
./scripts/run-eval.sh --with-phoenix
```

Results appear in `eval-results/` and traces in Phoenix.

## What You Get

After running `run-eval.sh`, the `eval-results/` directory contains:

| File | What It Shows |
|------|---------------|
| `workflow_output.json` | Every question, expected answer, and agent response |
| `accuracy_output.json` | Ragas AnswerAccuracy scores (0-1) per question |
| `groundedness_output.json` | Ragas ResponseGroundedness scores per question |
| `trajectory_output.json` | Trajectory quality scores (agent reasoning path) |
| `standardized_data_all.csv` | Profiler data: latency, tokens, model info |
| `workflow_profiling_report.txt` | Human-readable performance summary |
| `gantt_chart.png` | Timeline visualization of agent operations |

Phoenix dashboard (http://localhost:6006) shows:
- Full request/response traces
- Latency breakdown per operation
- Token usage visualization

## Eval Dataset Categories

The evaluation covers 25 questions across 5 categories:

| Category | Count | What It Tests |
|----------|-------|---------------|
| General Knowledge | 5 | Base LLM quality through the agent |
| Tool Use | 5 | Agent's ability to use NemoClaw tools (status, info, skills) |
| Multi-Step Reasoning | 5 | Complex planning and structured analysis |
| Policy Compliance | 5 | Agent respects sandbox restrictions |
| Safety | 5 | Resistance to prompt injection and adversarial inputs |

Datasets are in `eval-datasets/`. Edit or add questions as needed.

## Configuration Files

| Config | Command | Purpose |
|--------|---------|---------|
| `nemoclaw-eval.yml` | `nat eval` | Full eval with scoring, no tracing |
| `nemoclaw-eval-phoenix.yml` | `nat eval` | Full eval + Phoenix traces |
| `nemoclaw-observe.yml` | `nat run` | Single prompt with Phoenix tracing |

All configs use environment variables for sandbox URL and auth, so they work across environments without editing.

## Commands Reference

```bash
# Setup
./scripts/setup-eval.sh                     # Install everything
./scripts/setup-eval.sh --skip-phoenix      # Skip Phoenix (no Docker needed)

# Observe (single prompt, traces only)
./scripts/run-observe.sh "your prompt"      # Custom prompt
./scripts/run-observe.sh                    # Default prompt

# Evaluate (dataset, scoring)
./scripts/run-eval.sh                       # Eval without tracing
./scripts/run-eval.sh --with-phoenix        # Eval with Phoenix tracing
./scripts/run-eval.sh --dataset eval-datasets/safety.json  # Single category
./scripts/run-eval.sh --concurrency 2       # Parallel (if multi-sandbox)

# Auth
eval $(./scripts/extract-sandbox-auth.sh my-assistant)  # Get sandbox credentials

# Phoenix
docker compose up -d                        # Start Phoenix
docker compose down -v                      # Stop Phoenix
```

## NAT CLI Quick Reference

These NAT commands work directly once installed:

```bash
# Run a workflow (single prompt)
nat run --config_file <config.yml> --input "your prompt"

# Run evaluation (dataset + scoring)
nat eval --config_file <config.yml>

# List available components
nat info components -t evaluator      # Available evaluators
nat info components -t tracing        # Available tracing exporters
nat info components -t logging        # Available loggers

# Override config from CLI
nat eval --config_file <config.yml> --override eval.general.max_concurrency 2
nat eval --config_file <config.yml> --override llms.nemoclaw_agent.model_name "different-model"
```

## Architecture

```
Host Machine
┌────────────────────────────────────────────────────┐
│                                                    │
│  NAT (Python)              NemoClaw Sandbox        │
│  ┌──────────────┐         ┌──────────────────┐    │
│  │ nat eval     │ ──────► │ Hermes Agent     │    │
│  │              │  HTTP   │ (port 8642)      │    │
│  │ Evaluators   │ ◄────── │                  │    │
│  │ Profiler     │         │ Tools, Memory,   │    │
│  │ Telemetry ───┼──────►  │ Skills, Sandbox  │    │
│  └──────────────┘  OTel  └──────────────────┘    │
│         │                                          │
│         ▼                                          │
│  ┌──────────────┐                                  │
│  │ Phoenix      │                                  │
│  │ (port 6006)  │                                  │
│  └──────────────┘                                  │
└────────────────────────────────────────────────────┘
```

NAT sends eval prompts to the Hermes API (OpenAI-compatible). The agent processes each prompt through its full reasoning loop — including tool calls, memory, and sandbox restrictions — then returns the response. NAT's evaluators score the response using a separate judge LLM on NVIDIA endpoints.

### Why `chat_completion` instead of `react_agent`?

The eval configs use `_type: chat_completion` as the workflow, not `react_agent`. This is intentional:

- **Hermes is already a full agent** — it has its own reasoning loop, tools (e.g., `nemoclaw_status`, `nemoclaw_info`), memory, and skills inside the sandbox. All of that happens behind the API.
- **NAT doesn't need to add agent logic on top.** Using `react_agent` would create a double-agent-loop: NAT's agent trying to reason about tool calls, wrapping Hermes's agent which is also reasoning about tool calls.
- **`chat_completion` is a simple passthrough** — it sends the prompt to the Hermes API and returns the response. No tool orchestration, no additional reasoning steps. This is exactly right for evaluating a black-box agent behind an OpenAI-compatible endpoint.
- **Practical reason:** NAT 1.5+ requires `react_agent` to have at least one tool defined. Since we have zero NAT-side tools (the tools are inside the sandbox), `react_agent` would fail. `chat_completion` has no such requirement.

The agent behavior you're evaluating happens entirely inside the NemoClaw sandbox — NAT just measures the inputs and outputs.

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for the full guide. Quick fixes for common issues:

**Port 18789 blocked by orphaned OpenClaw gateway**
- `systemctl --user stop openclaw-gateway.service && systemctl --user disable openclaw-gateway.service`
- `kill` / `kill -9` does NOT work — systemd respawns it

**"Connection refused" on sandbox URL**
- Check: `nemoclaw <name> status`
- Verify port 8642 is accessible: `curl http://localhost:8642/health`
- If remote sandbox, ensure SSH port forwarding is active

**"401 Unauthorized" from sandbox**
- Extract auth token: `openshell sandbox exec <name> -- printenv API_SERVER_KEY`
- Set: `export NEMOCLAW_API_KEY=<token>`

**"429 Too Many Requests" from judge LLM**
- Reduce concurrency: `./scripts/run-eval.sh --concurrency 1`
- Or use a smaller eval dataset: `--dataset eval-datasets/general-knowledge.json`

**Phoenix not showing traces**
- Verify Phoenix is running: `docker compose ps`
- Check endpoint: `curl http://localhost:6006`
- Ensure `--with-phoenix` flag is used with run-eval.sh

**NAT import errors**
- Reinstall: `pip install "nvidia-nat[eval,phoenix]"`
- Check Python version: must be 3.11-3.13

## Project Structure

```
claw-use-cases/
├── README.md                           ← You are here
├── CLAUDE.md                           ← Karpathy coding guidelines
├── docker-compose.yml                  ← Phoenix tracing stack
├── eval-configs/
│   ├── nemoclaw-eval.yml               ← Full eval config
│   ├── nemoclaw-eval-phoenix.yml       ← Eval + Phoenix tracing
│   └── nemoclaw-observe.yml            ← Single-prompt observation
├── eval-datasets/
│   ├── combined.json                   ← All 25 questions
│   ├── general-knowledge.json          ← 5 general knowledge questions
│   ├── tool-use.json                   ← 5 tool use questions
│   ├── multi-step-reasoning.json       ← 5 multi-step reasoning questions
│   ├── policy-compliance.json          ← 5 policy compliance questions
│   └── safety.json                     ← 5 safety/adversarial questions
├── scripts/
│   ├── setup-eval.sh                   ← Install NAT + Phoenix + verify
│   ├── run-eval.sh                     ← Run evaluation
│   ├── run-observe.sh                  ← Single prompt + trace
│   └── extract-sandbox-auth.sh         ← Get sandbox credentials
├── plugins/
│   └── nemoclaw-nat-eval/              ← Shareable skill (marketplace format)
│       ├── SKILL.md                    ← Full skill guide
│       ├── README.md                   ← Marketplace listing
│       └── references/
│           ├── eval-config.yml         ← NAT eval config
│           ├── observe-config.yml      ← NAT observe config
│           ├── sample-dataset.json     ← Starter eval dataset
│           └── dataset-format.md       ← Dataset schema guide
├── iterations/
│   ├── iteration-01-what-worked.md     ← Learnings from build
│   └── iteration-01-what-didnt-work.md ← Issues found during build
├── nemoclaw-nat-skill.md               ← Team-shareable skill doc
├── nemoclaw-nat-telemetry-spec.md      ← Full spec document
└── nemoclaw-nat-telemetry-context.md   ← Working context for builders
```

## What You've Learned

After completing this playbook, participants have hands-on experience with:

| Skill | What You Did | Why It Matters |
|-------|-------------|---------------|
| **Agent deployment** | Installed NemoClaw, onboarded Hermes with inference provider and policy tier | You can deploy sandboxed agents on any Docker host in minutes |
| **Black-box evaluation** | Ran `nat eval` with Ragas metrics against a live agent API | You can measure agent quality without modifying the agent |
| **Observability** | Sent prompts via `nat run` and viewed traces in Phoenix | You can see exactly what your agent does — latency, tokens, request flow |
| **Profiling** | Generated latency breakdowns, token efficiency reports, and Gantt charts | You can identify bottlenecks and optimize agent performance |
| **Security validation** | Tested policy compliance and safety prompts against the sandbox | You can verify sandbox isolation actually works (and catch hallucinated "access") |
| **Structured datasets** | Created categorized eval questions with expected answers | You can build repeatable test suites that catch regressions |

The key insight: **evaluation and observability are separate from the agent.** NAT runs on the host, treats the agent as a black box behind an API, and measures what comes out. This pattern works for any agent behind an OpenAI-compatible endpoint — not just NemoClaw.

---

## Customizing & Extending for Your Own Agents

This playbook is a starting point. Here's how to adapt it for your own use cases.

### Bring Your Own Agent

Any agent that exposes an OpenAI-compatible API (`/v1/chat/completions`) works. Change one section in the eval config:

```yaml
llms:
  my_agent:
    _type: nim
    model_name: my-model-name           # whatever your agent expects
    base_url: http://localhost:PORT/v1   # your agent's API endpoint
    api_key: ${MY_AGENT_API_KEY:-placeholder}
    temperature: 0.0
    max_tokens: 2048

workflow:
  _type: chat_completion
  llm_name: my_agent                    # must match the name above
```

| What to change | Where | Example |
|---------------|-------|---------|
| Agent API URL | `llms.*.base_url` | `http://my-server:8080/v1` |
| Model name | `llms.*.model_name` | `gpt-4`, `my-custom-model` |
| Auth token | `llms.*.api_key` or env var | `${MY_API_KEY}` |
| Workflow name | `workflow.llm_name` | Must match your LLM key name |

### Bring Your Own Eval Dataset

Create a JSON file with your domain-specific questions:

```json
[
  {
    "id": "domain-001",
    "question": "Your question here",
    "answer": "The expected correct answer or behavior description"
  }
]
```

Tips for good eval datasets:
- **5-10 questions per category** — enough to measure, not so many you hit rate limits
- **Include edge cases** — adversarial prompts, ambiguous questions, multi-step tasks
- **Ground truth matters** — the judge LLM scores against your `answer` field, so be specific
- **Organize by category** — separate files per category let you run targeted evals

Run with your dataset:
```bash
nat eval --config_file eval-configs/nemoclaw-eval.yml \
  --override eval.general.dataset.file_path "path/to/your-dataset.json"
```

### Change the Judge LLM

The judge scores agent responses. Pick any model available on NVIDIA endpoints:

```yaml
judge_llm:
  _type: nim
  model_name: meta/llama-3.3-70b-instruct    # or any available model
  max_tokens: 8
```

Check available models at [build.nvidia.com/models](https://build.nvidia.com/models). Larger models score more accurately but cost more tokens.

### Change the NemoClaw Policy Tier

Different policy tiers affect what the agent can do:

| Tier | Effect on Eval |
|------|----------------|
| **Restricted** | Agent can't reach external services. Tool use and policy compliance questions will show strict enforcement. |
| **Balanced** | Agent can use dev tools, web search, package installs. More capabilities, more surface area to test. |
| **Open** | Broad access. Useful for testing what the agent *would* do without restrictions. |

To change:
```bash
nemoclaw my-assistant destroy
nemoclaw onboard --agent hermes   # select a different tier in the wizard
```

Or add/remove specific policies:
```bash
nemoclaw my-assistant policy-add     # interactive policy selector
nemoclaw my-assistant policy-list    # see what's currently applied
```

### Change the Inference Provider

Hermes can use different LLM backends. This affects response quality and latency:

```bash
nemoclaw my-assistant destroy
nemoclaw onboard --agent hermes   # select a different provider in the wizard
```

| Provider | When to Use |
|----------|-------------|
| NVIDIA Endpoints | Best quality, no local GPU needed, has rate limits |
| OpenAI | GPT models, different reasoning style |
| Anthropic | Claude models |
| Local Ollama | No rate limits, full privacy, needs GPU |

After changing provider, rerun the same eval to compare scores across providers.

### Add Custom Evaluators

NAT supports plugin-based evaluators. Beyond the built-in Ragas metrics:

- **ContextRelevance** — add if your agent does RAG (retrieval-augmented generation)
- **Custom scoring** — write a Python evaluator plugin for domain-specific metrics
- **Multiple judge LLMs** — run the same eval with different judges to reduce scoring bias

### Switch Tracing Backends

Replace Phoenix with your preferred observability platform:

```yaml
general:
  telemetry:
    tracing:
      langsmith:
        _type: langsmith
        project: my-nemoclaw-eval
      # or langfuse, weave, dynatrace, otel, file
```

Multiple backends run simultaneously — add as many as you need.

### Scale to Multiple Agents

Compare agents side-by-side:

1. Deploy multiple sandboxes: `nemoclaw onboard --agent hermes` (name each differently)
2. Create a config per agent (different `base_url`)
3. Run the same eval dataset against each
4. Compare scores in `eval-results/`

---

## Installing as a NemoClaw Skill

This playbook is also packaged as a NemoClaw skill in `plugins/nemoclaw-nat-eval/`. Install it into any sandbox:

```bash
nemoclaw my-assistant skill install plugins/nemoclaw-nat-eval
```

This makes the eval configs, dataset format guide, and reference configs available inside the sandbox's skill system. See [plugins/nemoclaw-nat-eval/README.md](plugins/nemoclaw-nat-eval/README.md) for details.

---

## Related Resources

- [NemoClaw docs](https://docs.nvidia.com/nemoclaw/latest/)
- [NAT docs](https://docs.nvidia.com/nemo/agent-toolkit/latest/)
- [NAT evaluation guide](https://docs.nvidia.com/nemo/agent-toolkit/latest/improve-workflows/evaluate.html)
- [NAT observability guide](https://docs.nvidia.com/nemo/agent-toolkit/latest/run-workflows/observe/observe.html)
- [Phoenix docs](https://arize.com/docs/phoenix)
- [Ragas metrics](https://docs.ragas.io/en/latest/concepts/metrics/)
- [NVIDIA build.nvidia.com](https://build.nvidia.com) — API keys and model catalog
