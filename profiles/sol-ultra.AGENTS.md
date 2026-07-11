<!-- SOL-ULTRA-WORKAROUND:BEGIN -->
## SOL Ultra managed delegation policy

This block is managed by SOL Ultra Workaround. User content outside these
markers is preserved.

Only the active root may spawn. Delegate only concrete, bounded work; direct
children must not spawn. Use the configured default child without inherited
context: V2 requires `fork_turns="none"`; legacy/V1 requires
`fork_context=false`. Never use a full or partial inherited-context fork.

Before every spawn, send a semantic handoff containing: Objective, Current
state, Binding decisions, Relevant files and evidence, Constraints, Known
failures, Child assignment, Acceptance criteria, Required output, and Open
questions. Omit raw transcripts, superseded output, repeated contents, filler,
and unrelated history.

Run at most three children concurrently and four distinct children per user
turn. Each child receives exactly one triggered turn: its initial spawn.
Never call `followup_task`. While a child is still running, `send_message` may
refine its current turn because that does not trigger another turn. Treat the
child as terminal after completion. Related work requires a fresh default child
with `fork_turns="none"` and a new semantic handoff. If the four-child budget is
exhausted, stop instead of reusing a child.

A child result is invalid until the root independently verifies from runtime
evidence that it used Terra High, high reasoning, no inherited parent turns,
and exactly one triggered child turn. Locate the child's matching rollout
JSONL under `$CODEX_HOME/sessions` (default `~/.codex/sessions`); require its
latest `turn_context` to report `model=gpt-5.6-terra` and `effort=high`,
`session_meta` to report `thread_source=subagent`, its input inventory to
contain no inherited parent dialogue, and exactly one
`inter_agent_communication_metadata` event with `trigger_turn=true`.
A child's self-report is not evidence. If runtime evidence is unavailable or
any requirement mismatches, reject the result and stop instead of accepting,
retrying, or taking over. Then verify material claims against files, commands,
or tests.

If Terra High is unavailable or fails an acceptance criterion, explain the
specific deficiency and stop. Ask exactly: "Terra High could not complete this
reliably. Approve SOL Ultra root takeover? Reply APPROVE_SOL_ULTRA_TAKEOVER or
DECLINE." Do not take over, change configuration, or retry with a stronger or
faster setup until the user explicitly approves.
<!-- SOL-ULTRA-WORKAROUND:END -->
