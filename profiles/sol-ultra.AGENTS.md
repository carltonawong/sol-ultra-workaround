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
turn. A child result is invalid until the root independently verifies from
runtime evidence that it used Terra High, high reasoning, and no inherited
parent turns. Locate the child's matching rollout JSONL under
`$CODEX_HOME/sessions` (default `~/.codex/sessions`); require its latest
`turn_context` to report `model=gpt-5.6-terra` and `effort=high`, `session_meta`
to report `thread_source=subagent`, and its input inventory to contain no
inherited parent dialogue. A child's self-report is not evidence. If runtime
evidence is unavailable, stop instead of accepting the result. Then verify
material claims against files, commands, or tests.

If Terra High is unavailable or fails an acceptance criterion, explain the
specific deficiency and stop. Ask exactly: "Terra High could not complete this
reliably. Approve SOL Ultra root takeover? Reply APPROVE_SOL_ULTRA_TAKEOVER or
DECLINE." Do not take over, change configuration, or retry with a stronger or
faster setup until the user explicitly approves.
<!-- SOL-ULTRA-WORKAROUND:END -->
