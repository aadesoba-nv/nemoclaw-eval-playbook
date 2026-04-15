# Iteration 01 — What Worked

**Date:** 2026-04-14
**Focus:** Phase 1 scaffolding — project structure, eval dataset, NAT configs, scripts, Phoenix setup, Hermes setup guide, skill doc

---

## 1. Treating Hermes API as an OpenAI-compatible LLM endpoint

NAT's `nim` LLM type supports a `base_url` parameter. Pointing it at the Hermes sandbox API (`http://localhost:8642/v1`) lets NAT communicate with the full NemoClaw agent using standard OpenAI chat completions format. No custom adapter needed.

**Key config pattern:**
```yaml
llms:
  nemoclaw_agent:
    _type: nim
    model_name: hermes
    base_url: http://localhost:8642/v1
    api_key: ${NEMOCLAW_API_KEY}
```

## 2. react_agent with no tools as passthrough

NAT's `react_agent` workflow with `tool_names: []` effectively acts as a direct LLM passthrough — it sends the prompt as a chat completion and returns the response. This is exactly right for NemoClaw because the agent already has its own tool loop internally. Adding NAT tools on top would create a double-agent-loop problem.

## 3. Environment variable substitution in YAML configs

NAT supports `${ENV_VAR:-default}` syntax in YAML configs. This lets us create configs that work across environments (local, remote DGX, hackathon machines) without editing files:
- `NEMOCLAW_SANDBOX_URL` — sandbox API endpoint
- `NEMOCLAW_API_KEY` — sandbox bearer token
- `PHOENIX_ENDPOINT` — tracing endpoint

## 4. Separate eval and observe configs

Two distinct usage patterns emerged:
- **Observe** (`nat run`): Single prompt, full tracing, for live demos and interactive exploration
- **Evaluate** (`nat eval`): Dataset-driven, scoring, profiling, for systematic quality assessment

Keeping these as separate configs avoids cluttering the observe path with eval-specific settings.

## 5. Category-based eval datasets

Splitting the dataset into 5 JSON files by category (general knowledge, tool use, multi-step reasoning, policy compliance, safety) allows:
- Running single-category evals for focused testing
- Combining into `combined.json` for full suite
- Partners can add their own category files

## 6. Phoenix as single-container observability

Phoenix in a single Docker container provides both the OTel gRPC receiver (port 4317) and the web UI (port 6006). No complex multi-service setup needed. The `docker-compose.yml` is minimal.

## 7. Script-based workflow

Three scripts cover the full lifecycle:
- `setup-eval.sh` — one-time install and verification
- `run-eval.sh` / `run-observe.sh` — repeatable execution
- `extract-sandbox-auth.sh` — credential extraction

This keeps the README clean and gives partners copy-paste commands.

## 8. Profiler integration in eval config

NAT's profiler runs alongside evaluation when enabled in the eval config. This gives us token efficiency, latency analysis, and Gantt charts for free — no extra setup. The `compute_llm_metrics: true` flag is key.

## 9. judge LLM on NVIDIA endpoints

Using `nvidia/llama-3.3-nemotron-super-49b-v1` as the judge LLM (hosted on NVIDIA endpoints) means participants only need an API key — no local GPU for the judge. It's the top-ranked evaluator model in Ragas benchmarks.

## 10. Marketplace skill format (SKILL.md + references/)

NemoClaw's skill format (`SKILL.md` with YAML frontmatter `name` + `description`, plus a `references/` directory for supporting files) works well for packaging the NAT integration as a shareable skill. The `plugins/nemoclaw-nat-eval/` directory follows the same structure as the `hermes-brev` skill in the tao-skill-marketplace and can be dropped into NemoClaw's `.agents/skills/` or the marketplace `plugins/` directory.

## 11. Hermes setup as Part 0 in the playbook

Adding the full NemoClaw Hermes onboarding flow (install, onboard with `--agent hermes`, verify, extract auth) as a prerequisite section in the README makes the playbook self-contained. Participants don't need to reference separate NemoClaw docs — everything is in one document. The `nemoclaw onboard --agent hermes` command plus the non-interactive variant cover both hackathon and scripted CI use cases.

## 12. NemoClaw CLI reference table in the skill

Including a concise CLI reference table (not the full docs, just the 12 most-used commands) in both the README and the SKILL.md gives partners immediate context. Especially useful: `nemoclaw <name> status`, `nemoclaw <name> connect`, and `openshell sandbox exec` for auth extraction.

## 13. NVIDIA Brev as the zero-infra deployment path

Brev eliminates the "I don't have a machine" blocker for hackathon participants. Key wins:
- CPU-only instances are sufficient (~$0.10/hr) since inference goes to NVIDIA Endpoints
- Docker, Python, NVIDIA drivers all pre-installed — no setup friction
- `brev port-forward` tunnels Phoenix dashboard to local browser seamlessly
- `brev create` + `brev shell` + standard NemoClaw install = full environment in ~5 minutes
- Non-interactive onboarding (`--non-interactive --yes-i-accept-third-party-software`) makes Brev setup scriptable
