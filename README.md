# Codex Subagent Budget

A small, temporary workaround for Codex sessions where an expensive root agent
silently spawns equally expensive subagents and forks the full conversation into
each one.

This project contains no executable code. It is two snippets:

- `config.toml.snippet` exposes Codex's existing per-spawn model controls and
  keeps the session at three concurrent child agents.
- `AGENTS.md.snippet` tells a SOL Ultra root to use Terra High workers with no
  inherited conversation, and to ask before escalating.

It is intentionally not a plugin, hook, MCP server, daemon, or telemetry tool.

## The workaround

Codex 0.144 already accepts `model`, `reasoning_effort`, `service_tier`, and
`fork_turns` on MultiAgentV2 `spawn_agent` calls. However, the model-selection
fields are hidden by default, and omitting `fork_turns` defaults to `all`.
Full-history forks reject model and reasoning overrides.

The workaround therefore does two things:

1. Make the existing spawn controls visible to the root agent.
2. Require economical, context-light defaults whenever the root is SOL Ultra.

Relevant upstream implementation:

- [Spawn handler](https://github.com/openai/codex/blob/rust-v0.144.0/codex-rs/core/src/tools/handlers/multi_agents_v2/spawn.rs)
- [Spawn tool schema](https://github.com/openai/codex/blob/rust-v0.144.0/codex-rs/core/src/tools/handlers/multi_agents_spec.rs)
- [MultiAgentV2 configuration](https://github.com/openai/codex/blob/rust-v0.144.0/codex-rs/core/src/config/mod.rs)
- [Upstream full-history override issue](https://github.com/openai/codex/issues/20077)

## Install

Requires Codex 0.144.0 or a compatible build with MultiAgentV2.

1. Merge the contents of `config.toml.snippet` into
   `~/.codex/config.toml`. Do not replace the rest of your config.
2. Append `AGENTS.md.snippet` to `~/.codex/AGENTS.md`. Create the file if it
   does not exist.
3. Fully quit and restart Codex, then start a new task.

If `[features.multi_agent_v2]` already exists, add the three keys to that existing
table instead of creating a duplicate TOML table. If your `[features]` table
already contains `multi_agent_v2 = true`, remove that scalar entry and use the
nested table from the snippet instead; `enabled = true` preserves the setting.

## Default policy

When the root is `gpt-5.6-sol` at `ultra`, each child must use:

```text
model: gpt-5.6-terra
reasoning: high
service tier: default
fork_turns: none
```

The root may run no more than three children concurrently and no more than four
distinct children in one user turn, including replacements. A stronger child
requires explicit user approval.

`fork_turns="none"` means the root must send a self-contained task capsule. This
avoids replaying a large parent conversation into every child and is also what
makes model and reasoning overrides compatible with current MultiAgentV2.

## Security and privacy

This workaround:

- executes no code;
- opens no network connections;
- installs no hook or background process;
- requests no filesystem, shell, browser, or account permissions;
- reads and uploads no telemetry;
- does not change sandbox or approval settings.

It only changes which existing `spawn_agent` fields Codex shows to the root
model and adds local written guidance for how to use them.

## Limitations

- This is a behavioral guardrail, not a hard billing or security boundary.
- It cannot calculate how OpenAI's five-hour allowance is debited.
- Approval buttons are not a universal interception hook. Codex should use a
  structured prompt when the current app/mode exposes one and plain text when
  it does not.
- A closer project-level `AGENTS.md` can override global guidance.
- Model availability varies by plan and Codex version. The policy tells Codex
  to ask rather than silently inherit SOL Ultra when Terra is unavailable.
- Codex may change or remove the under-development MultiAgentV2 configuration.
  Remove this workaround when upstream behavior becomes safe by default.

## Uninstall

Remove the copied `[features.multi_agent_v2]` keys and the section headed
`SOL Ultra subagent budget` from `~/.codex/AGENTS.md`, then restart Codex.

## Why this is not a skill

A skill is loaded after it triggers. This policy needs to be present before an
autonomous spawn decision, so the smallest reliable surface is global
`AGENTS.md`. Keeping the workaround to two declarative files also makes it easy
to inspect, audit, and remove.

## Status

Unofficial workaround, intended to be temporary until Codex exposes economical
subagent defaults and context-fork controls directly in the product.
