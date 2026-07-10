# SOL Ultra Workaround

A small, temporary workaround for Codex sessions where a SOL Ultra root can
spawn equally expensive children and fork the full conversation into each one.

This project contains no executable code. It uses three declarative files:

- `config.toml.snippet` sets stable concurrency and recursion limits.
- `agents/default.toml` overrides Codex's default child with Terra High.
- `AGENTS.md.snippet` requires context-light spawning and approval before
  escalation.

## Why this design

Codex 0.144 has local code for per-spawn model and reasoning overrides, but the
SOL backend reserves the `collaboration.spawn_agent` tool schema. Exposing the
hidden fields causes the request to fail before the model runs:

```text
Function 'collaboration.spawn_agent' is reserved for use by this model and
must match the configured schema.
```

This workaround leaves that schema untouched. Codex officially supports custom
agents that override normal session settings, and a custom agent named
`default` replaces the built-in fallback used for ordinary child spawns.

- [Official custom-agent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents)
- [Official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference#configtoml)
- [Codex 0.144 spawn handler](https://github.com/openai/codex/blob/rust-v0.144.0/codex-rs/core/src/tools/handlers/multi_agents_v2/spawn.rs)

## Install

Tested with Codex CLI 0.144.0. Fully quit and restart Codex after installing,
then start a new task.

1. Merge `config.toml.snippet` into `~/.codex/config.toml`.
2. Copy `agents/default.toml` to `~/.codex/agents/default.toml`.
3. Append `AGENTS.md.snippet` to `~/.codex/AGENTS.md`.

Do not create duplicate `[features]` or `[agents]` TOML tables. Add the keys to
an existing table when one is already present.

Do not overwrite an existing `~/.codex/agents/default.toml`. Review it and
merge the model settings manually, or install this workaround only inside one
trusted project using `.codex/agents/default.toml` and project-scoped config.

## Effective policy

The default child runs with:

```text
model: gpt-5.6-terra
reasoning: high
service tier: default
fork_turns: none
```

`agents.max_threads = 4` gives the root three concurrent child slots.
`agents.max_depth = 1` prevents children from spawning grandchildren. The
written policy also limits one user turn to four distinct children, including
replacements.

Because `fork_turns="none"` starts a clean child context, the root must send a
self-contained task capsule containing the objective, relevant paths,
constraints, expected output, and verification criteria.

## End-to-end validation

The primary path was tested on July 10, 2026 in a disposable `CODEX_HOME` and a
read-only canary workspace. The recorded parent and child rollouts confirmed:

| Check | Recorded result |
| --- | --- |
| Root | `gpt-5.6-sol`, `ultra` |
| Spawn call | Reserved schema unchanged; `fork_turns="none"` |
| Child | `gpt-5.6-terra`, `high` |
| Child policy | Custom developer instructions loaded |
| Concurrency | Four total slots advertised: root plus three children |
| Canary | Child read and returned the expected value |
| Isolation | Existing config, global guidance, and auth hashes unchanged |

The child config's `service_tier = "default"` was accepted by the successful
run, but Codex does not echo service tier in its rollout metadata, so that field
was not independently observed in the recorded trace. The three-child ceiling
comes from Codex's stable `agents.max_threads` enforcement; the test did not
deliberately saturate all slots and waste three extra child calls.

## Security and privacy

This workaround:

- executes no code;
- opens no network connections;
- installs no hook or background process;
- requests no filesystem, shell, browser, or account permissions;
- reads or uploads no telemetry;
- does not weaken sandbox or approval settings.

The custom child inherits the parent's sandbox and tools unless you explicitly
restrict them further.

## Limitations

- This is a behavioral and configuration guardrail, not a billing boundary.
- Overriding the `default` agent affects ordinary unnamed child spawns from all
  parent models, not only SOL Ultra. Current Codex cannot condition a custom
  default agent on the parent model.
- The hard limit is three concurrent children. The four-distinct-children per
  turn limit remains written guidance.
- The reserved spawn schema does not currently permit a per-call model upgrade.
  If Terra is insufficient, the policy asks before the SOL Ultra root takes the
  work back or before the user changes agent configuration.
- Approval buttons depend on the current Codex surface and mode; plain-text
  confirmation is the fallback.
- Model availability and custom-agent behavior can change across Codex builds.

## Uninstall

Remove the copied `agents.max_threads`, `agents.max_depth`, and optional
`features.multi_agent` keys; remove `~/.codex/agents/default.toml`; and remove
the section headed `SOL Ultra subagent budget` from global `AGENTS.md`. Restart
Codex afterward.

## Status

Unofficial workaround, intended to be removed when Codex exposes supported
per-spawn model, reasoning, tier, context, and budget controls directly.
