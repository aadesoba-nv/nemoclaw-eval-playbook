# Iteration 01 — What Didn't Work

**Date:** 2026-04-14
**Focus:** Phase 1 scaffolding — project structure, eval dataset, NAT configs, scripts, Phoenix setup

---

## 1. NAT's `--endpoint` flag for remote workflow evaluation

Initially considered using `nat eval --endpoint http://localhost:8642/v1` to point NAT at the sandbox directly. This does NOT work because the `--endpoint` flag expects a NAT workflow server exposing `/generate/full`, not an arbitrary OpenAI-compatible API. Had to use the LLM `base_url` approach instead.

**Workaround:** Define the sandbox as an LLM in the config with `base_url` pointing to the Hermes API.

## 2. Direct NAT instrumentation inside the sandbox

Layer 3 (in-sandbox NAT telemetry) is not viable for the hackathon MVP:
- Requires modifying the NemoClaw Dockerfile to install `nvidia-nat`
- Hermes's plugin hook system (`on_llm_call`, `on_tool_call`) is not well documented
- Sandbox network policy would need egress rules for telemetry export
- OpenClaw (Node.js) can't use NAT at all

**Decision:** Defer to Phase 2. Layer 2 (external eval harness) is sufficient for hackathon.

## 3. Trajectory evaluation visibility

NAT's trajectory evaluator scores agent reasoning steps, but when the agent is behind an API (black box), NAT only sees the final response — not the intermediate tool calls and reasoning that happened inside the Hermes agent. The trajectory score will be based on the visible output structure, not the actual agent internals.

**Mitigation:** The trajectory evaluator can still assess whether the response *shows* structured reasoning. For deeper trajectory data, we'd need Layer 3 (in-sandbox instrumentation) or Hermes to expose intermediate steps in its API response.

## 4. Auth token management

The NemoClaw sandbox uses `API_SERVER_KEY` for bearer token auth, but extracting it programmatically requires `openshell sandbox exec` which needs the sandbox name. There's no standardized way to discover the sandbox name from outside. The `extract-sandbox-auth.sh` script handles the known case but may need manual intervention.

**Workaround:** Script requires sandbox name as argument. Fallback: manual extraction via `nemoclaw connect` then `echo $API_SERVER_KEY`.

## 5. ContextRelevance evaluator may not apply

The Ragas `ContextRelevance` metric evaluates whether retrieved context is relevant to the question. But our NemoClaw agent doesn't expose its retrieval context through the API response. Removed this metric from the eval config — using only `AnswerAccuracy` and `ResponseGroundedness` which work on question + answer alone.

**Note:** If we add RAG capabilities to the eval (e.g., document-backed questions), ContextRelevance becomes relevant again.

## 6. Rate limiting on NVIDIA endpoints

Running 25 eval questions with 3 evaluators = 75+ judge LLM calls. At `max_concurrency: 1` this is slow but safe. Increasing concurrency risks 429 errors from NVIDIA endpoints.

**Mitigation:** Default to `max_concurrency: 1`. Document the `--concurrency` flag for users with higher rate limits or local NIM deployments.

## 7. Model name mismatch uncertainty

NAT's `nim` LLM type sends the `model_name` parameter in the chat completion request. The Hermes API may or may not validate this field. If it expects a specific model name (matching its config), using `hermes` as model name might fail. This needs live testing against an actual sandbox.

**Workaround:** Made `model_name` easily overridable via CLI: `--override llms.nemoclaw_agent.model_name "actual-model-name"`

## 8. No dry-run capability

There's no way to validate the eval config without actually sending requests to the sandbox and judge LLM. A `nat eval --dry-run` that checks config syntax, dataset format, and endpoint reachability would be useful.

**Workaround:** The `setup-eval.sh` script performs preflight checks (Python version, NAT installed, sandbox reachable, API key set) as a manual dry-run.

## 9. Could not access tao-skill-marketplace GitLab repo

The `gitlab-master.nvidia.com` repo for the skill marketplace is internal and requires SSO auth. Could not clone or read the `hermes-brev` or `openclaw-brev` skill files to mirror exactly. Had to infer the plugin structure from NemoClaw's own `.agents/skills/` format and common marketplace conventions.

**Workaround:** Built the `plugins/nemoclaw-nat-eval/` skill using NemoClaw's native `SKILL.md` + `references/` format, which is compatible with both the NemoClaw skill system (`nemoclaw <name> skill install`) and should be droppable into the marketplace `plugins/` directory. Needs verification once GitLab access is available.

## 10. Hermes `--agent hermes` flag not in quickstart docs

The NemoClaw quickstart docs only show the OpenClaw default agent. The `--agent hermes` flag is documented in the `nemoclaw onboard` command reference but not prominently. Partners may miss it. Included explicit Hermes onboarding steps in the playbook to avoid confusion.
