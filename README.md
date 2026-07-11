# SOL Ultra Workaround

An experimental, reversible Codex 0.144 workaround for keeping SOL Ultra
subagent use more predictable.

It gives an opt-in SOL Ultra root a Terra High default child, asks the root to
keep delegation to three active children (four distinct children per turn at
most), treats completed children as terminal, and asks it to send concise
semantic handoffs instead of full-history forks.

This is an unofficial configuration workaround, not a billing boundary or an
OpenAI-supported quota control.

## One-prompt install

Send this one line from the Codex task you want to configure:

```text
Install this release v0.3.1 for the Codex surface and project this task started in: https://github.com/carltonawong/sol-ultra-workaround
```

The install contract directs Codex to pin `v0.3.1`, read
[`INSTALL.md`](INSTALL.md), and remember the original task location before
using a temporary clone. CLI automatically gets the opt-in profile. Desktop
automatically gets project mode when the task has one safe local project; a
projectless Desktop task offers either a dedicated `SOL Ultra Tasks` project or
an existing folder. IDE automatically uses one safe workspace root and asks for
an existing root when the workspace is ambiguous. Codex does not guess or
change global settings. It runs the shipped installer, verifies the
installation, and returns the surface-specific activation step.

A bare URL can look like a review request, so include an explicit install
instruction like the example above.
You do not need to supply a project path unless Codex asks for it.

## Desktop: `New task` by itself is not enough

The top-level **New task** action can create a projectless task. Projectless
tasks do not load a folder's `.codex/config.toml`, so they cannot activate this
workaround merely by being new.

For general Desktop work that is not tied to a codebase, use one dedicated
local project:

1. Start a top-level projectless task and paste the one-prompt install above.
2. When asked, reply `CREATE DEDICATED PROJECT`.
3. Codex creates and configures `~/SOL Ultra Tasks` only if that destination is
   safe and unused.
4. In Desktop, add or open that folder as a **Local Project** and trust it.
5. Select that project and choose **New task** inside it.

Fresh tasks created inside that trusted local project load the workaround when
no higher-precedence setting overrides it. A top-level projectless **New task**
does not. If the task needs to edit an existing codebase, configure that
codebase's own local project instead of the general-purpose folder.

- [Official Codex guidance for projectless tasks and local projects](https://learn.chatgpt.com/docs/projects)

## Does it meaningfully reduce usage?

Yes, on the child side, with two separate effects:

1. OpenAI's current Codex rate card assigns Terra exactly half the credits per
   million input, cached-input, and output tokens compared with Sol. Holding
   token volume constant, routing a child from Sol to Terra cuts that child's
   published credit cost by 50%.
2. A non-full fork (`fork_turns="none"` in V2 or `fork_context=false` in V1)
   prevents the parent transcript and raw tool history from becoming the
   child's starting context. The semantic handoff sends only the state needed
   for that assignment.

In the real long-running task that motivated this workaround, 39 direct child
rollouts were audited. Version 0.3.1 corrects the figures published in v0.3.0:
the earlier audit added each rollout's final cumulative counter, but forked
rollout files also contain copied parent counter history. The corrected method
subtracts the cumulative baseline immediately before every triggered child
turn, then sums only those child-turn deltas.

| Recorded child activity | Result |
| --- | ---: |
| Direct children | 39 |
| Actual child turns | 83 |
| Model and reasoning | 39 x `gpt-5.6-sol`, `ultra` |
| Child-only input tokens | 168,248,551 |
| Cached input tokens | 162,108,672 (96.35%) |
| Uncached input tokens | 6,139,879 |
| Output tokens | 905,034 |
| Reasoning output | 319,387 (included in output) |

At the published rate-card ratio, the same token mix on Terra would consume
50% fewer child credits. That is a model-only inference, not a replay: Terra may
use a different number of tokens, and Codex does not expose an exact conversion
from a task trace to the five-hour allowance.

This reduces inherited starting context, but its net token savings have not
been isolated as a single percentage. The potential benefit grows with the
size of the parent task and number of children. The SOL Ultra root still
consumes SOL Ultra usage, and each child still carries its own system, tool,
skill, and growing task context.

A later 13-child implementation run exposed a separate routing issue and
measured the workaround under real use:

| Child-run activity | Result |
| --- | ---: |
| Child rollouts / actual turns | 13 / 19 |
| Began on Terra High | 11 of 13 |
| Stayed entirely on Terra High | 9 of 13 |
| Terra High / SOL Ultra turns | 15 / 4 |
| Child-only input tokens | 12,655,295 |
| Cached input tokens | 11,524,352 (91.06%) |
| Output tokens | 142,575 |

Two full-history children ran entirely on SOL Ultra. Two other children began
isolated on Terra High but silently changed to SOL Ultra when a completed child
was triggered again. At the published token-credit rates, the
observed mix was 36.47% lower credit-equivalent than the same recorded tokens
all on SOL. If those two follow-up turns had stayed on Terra, the reduction
would have been 47.25%. This is trace arithmetic, not an account-billing or
five-hour-limit measurement, and the implementation tasks were not a
controlled performance comparison.

That task began before the final v0.3 managed policy was loaded into its root,
so it is evidence of the runtime routing edge case and observed usage, not a
clean v0.3.0 compliance test.

Within that run, the two full-history children averaged 20,856.5 initial input
tokens and the 11 isolated children averaged 16,080, a 22.9% smaller starting
context. The samples did different work, and most full-history input was
cached, so this is directional context evidence rather than a claim of 22.9%
uncached-token or allowance savings.

### Why completed children are now terminal

Codex 0.144 does not expose a model or reasoning argument on the operation that
re-triggers a completed child. In the run above, two such follow-ups reverted
from Terra High to SOL Ultra. Version 0.3.1 therefore uses a fail-closed policy:

- never call `followup_task`; each child receives only its initial turn;
- refine only a currently running turn with a non-triggering message;
- put later work in a fresh isolated default child;
- reject any result whose rollout does not show Terra High, high reasoning,
  isolated context, and exactly one triggered child turn.

This is the strongest configuration-and-policy guard available in Codex 0.144,
not a hard engine-level model lock. Internal collaboration operations cannot be
intercepted by hooks, so a root that disobeys the policy can still cause drift;
the independent rollout check is intended to prevent accepting that result.

- [Official Codex pricing and token-credit rates](https://learn.chatgpt.com/docs/pricing#what-are-tokens-and-credits)
- [Official Codex usage-limit explanation](https://learn.chatgpt.com/docs/pricing#what-are-the-usage-limits-for-my-plan)

## Scope: no global default override

The first prototype installed `~/.codex/agents/default.toml`. That affected
unnamed child spawns from every parent model, so it is no longer the recommended
design. The current installer detects that global file and stops; users of the
old prototype must review and remove its manual global edits before installing
this scoped version.

The current design is additive:

- **CLI:** an explicit `sol-ultra` profile. Normal launches are untouched.
- **Codex Desktop and IDE extension:** a dedicated project-local
  configuration. Other projects are untouched; new tasks in that configured
  project are pinned to the SOL Ultra setup unless the user overrides it.

The CLI profile footprint is exactly two TOML files plus a tiny local hash
manifest. Project mode additionally stores an installed copy of the managed
guidance block and appends that block to the selected project's active root
guidance file. When that file already exists, it records an installer-owned
exact backup for reversible uninstall. Nothing runs in the background after
installation.

Codex 0.144 has no supported runtime condition meaning "apply this default
agent only if the current parent is SOL Ultra." Profiles provide opt-in CLI
scoping; project configuration provides directory scoping for Desktop/IDE.

### Why there is no "SOL Ultra selected" pop-up

Codex loads profile and project configuration when a task starts. A lifecycle
hook can inspect the active model and show a warning, but there is no
model-selection event, the hook does not receive the reasoning effort needed to
distinguish Ultra from High or Medium, and it cannot load a CLI profile or
replace the already-loaded task configuration. It would also require a global
script and hook-trust prompt affecting unrelated tasks. Hooks also cannot
intercept Codex's internal `spawn_agent` operation, so they cannot enforce this
package's root-only-spawn policy. This package installs no hook, watcher,
daemon, or global `AGENTS.md` rule. CLI activation stays explicit; Desktop/IDE
activation stays project-local through the selected project's active guidance.

## Install

The installers refuse to overwrite package targets. They never modify the
user's base `config.toml`, global `AGENTS.md`, global `AGENTS.override.md`, or
global `agents/default.toml`. Project mode does deliberately append one
managed, marked block to the selected project's active root guidance file,
preserving content outside the markers and recording an exact backup when that
file already exists. Uninstall restores that backup when the file is otherwise
unchanged; if the user changed it later but the canonical block is intact, it
removes only the block and preserves the user's other changes.

Codex still needs normal permission to clone/read the repository and write the
documented scoped targets. The installer performs no network request itself.

### CLI profile — recommended

Windows PowerShell:

```powershell
./install.ps1 -Mode profile
codex --profile sol-ultra
```

macOS or Linux:

```sh
./install.sh profile
codex --profile sol-ultra
```

The installer adds only:

```text
~/.codex/sol-ultra.config.toml
~/.codex/sol-ultra-workaround/terra-high.toml
~/.codex/sol-ultra-workaround/install-state.txt
```

Normal `codex` launches do not load those files. Use `--profile sol-ultra` on
every new or resumed CLI task that should use the workaround. A project-local
`.codex/config.toml` has higher precedence and may defeat the profile; the
one-prompt installer stops if the current project has that conflict.

### Codex Desktop or IDE project mode

Desktop and the IDE extension do not expose the CLI profile selector. Install
only into a dedicated trusted project that should default to SOL Ultra:

```powershell
./install.ps1 -Mode project -ProjectRoot C:\path\to\project
```

```sh
./install.sh project /path/to/project
```

Project mode refuses an existing `.codex/config.toml` or
`.codex/agents/default.toml`, the user's home directory, and the downloaded
package checkout instead of merging, overwriting, or broadening scope. It adds
these package-owned files:

```text
<project>/.codex/config.toml
<project>/.codex/sol-ultra-workaround/terra-high.toml
<project>/.codex/sol-ultra-workaround/guidance-block.md
<project>/.codex/sol-ultra-workaround/install-state.txt
```

It also updates the project's active root guidance: `AGENTS.override.md` when
present, otherwise `AGENTS.md`. The appended block is delimited exactly by
`<!-- SOL-ULTRA-WORKAROUND:BEGIN -->` and
`<!-- SOL-ULTRA-WORKAROUND:END -->`; user content outside those markers is
preserved. If the active file existed, its exact pre-install contents are
backed up at `<project>/.codex/sol-ultra-workaround/<active-file>.preinstall.bak`.
If neither root guidance file existed, the installer creates `AGENTS.md` with
the canonical block. A symlink, non-regular file, or pre-existing managed
marker is a conflict, not a merge opportunity.

Desktop: add or open the folder as a trusted Local Project, then create a fresh
task inside that project. IDE: open and trust the configured folder or
workspace, then start a fresh task there. If Codex 0.144 does not pick up a
project layer installed while the client was already open, fully restart the
client and try the fresh task again.

## Existing tasks

Start a new task after installation. On Codex 0.144, this is required for the
complete policy to load reliably: start the CLI task with
`--profile sol-ultra`, or create the task inside the configured trusted
project. A top-level projectless Desktop **New task** does not load the
workaround.

An existing task does not meet this activation requirement. After a cold
restart it may still use the routing change, but do not treat a resumed task as
proof that the complete managed policy loaded:

- fully stop and restart the Codex backend first;
- CLI: resume with
  `codex resume --profile sol-ultra <SESSION_ID_OR_NAME>`;
- Desktop/IDE: resume from a project containing the project-mode configuration;
- only newly spawned, compliant default-role children using a non-full fork are
  routed to Terra High. Existing children, named roles, and full-history forks
  keep or can inherit other settings.

An isolated 0.144 test applied equivalent child routing and fresh AGENTS
guidance to a task created before installation. After a cold restart, the same
task resumed and its next child recorded `gpt-5.6-terra` with `high` reasoning.
That proves newly spawned children can change after a cold resume; it does not
remove the developer-instruction caveat below.

There is one version-specific caveat: plain `developer_instructions` changes
are not guaranteed to become model-visible when an old 0.144 task resumes. A
fresh task avoids that bug. If resuming is essential, explicitly remind the
root to use the semantic-handoff and approval policy; the child routing itself
was verified after resume.

## Effective policy

When the profile or dedicated project configuration is active:

```text
root:              gpt-5.6-sol / ultra
default child:     gpt-5.6-terra / high
requested tier:    default (not independently echoed in traces)
V2 child fork:     fork_turns="none"
V1 child fork:     fork_context=false
child lifecycle:   one triggered turn; fresh child for later work
V2 concurrency:   built-in root plus three active children
policy ceiling:   three active; four distinct children per user turn
nesting:          V1 depth one; V2 root-only-spawn policy is behavioral
```

Mechanical controls and runtime limits:

- the declared `default` role's Terra High model and reasoning on a compliant
  non-full default-role spawn;
- V2's built-in four active slots include the root, leaving three active child
  slots by default, unless another managed setting overrides that default;
- `max_depth=1` prevents V1 grandchildren; `max_threads=3` is the configured
  child-thread ceiling. Codex 0.144 V2 ignores `max_depth`.

Behavioral instructions, not mechanically enforced (only selected behaviors
below were exercised in scenarios):

- choosing the correct non-full fork field for V1 or V2;
- building the semantic handoff;
- root-only spawning and the V2 no-grandchildren rule;
- no more than four distinct children per user turn;
- treating a completed child as terminal and never using `followup_task` on it;
- rejecting a child result until routing, high reasoning, and isolated context
  plus exactly one triggered turn are independently verified from runtime
  evidence, and stopping when that evidence is unavailable;
- stopping for approval before SOL Ultra root takeover.

Important: in Codex 0.144, a full-history spawn bypasses the custom role layer,
and a completed-child follow-up can change back to SOL Ultra. Terra routing
therefore depends on the root following both the non-full-fork and
single-trigger instructions. The rollout verification fails closed after a
mismatch; it cannot prevent the mismatched turn from having already run.

## Validation

Installer and routing-suite tests used disposable Codex homes. The Desktop
canary below used a disposable project with the live Desktop backend and
archived its test threads. A test-only attempt to supply trust through the
app-server persisted one dummy trust entry; cleanup removed that exact entry
and revalidated the base config. The released installer never writes trust or
edits the base config.

### v0.3.1 single-trigger canary

A fresh Codex CLI 0.144.0 SOL Ultra root performed two delegated checks in
sequence. It waited for the first child to finish, verified that rollout, then
created a distinct fresh child for the second check. Independent trace review
confirmed:

- the root recorded `gpt-5.6-sol` with `ultra` reasoning;
- its trace contained two `spawn_agent` calls and zero `followup_task` calls;
- both child traces recorded `gpt-5.6-terra`, `high`, and
  `thread_source=subagent`;
- each child trace contained exactly one `trigger_turn=true` event and no
  inherited parent request.

This exercises the completed-child replacement behavior. It remains a
model-followed policy canary, not proof of a hard engine lock.

### Profile child-role isolation

The same sandbox was run twice:

| Launch | Root | Default child |
| --- | --- | --- |
| With test profile | Luna Low | Terra High with profile child policy |
| Without profile | Luna Low | Luna Low with no profile child policy |

Both runs intentionally used the same command-line Luna Low root override so
the test isolated only the profile's child-role effect. This confirmed that the
declared child is scoped to the selected profile and does not alter normal
launches.

### SOL Ultra/V2 semantic-handoff suite

One SOL Ultra parent remained alive for five turns and spawned three Terra High
children with `fork_turns="none"`:

- a noisy-history child recovered the required facts but inherited none of 30
  garbage markers;
- a stale-decision child re-read files and rejected superseded state;
- a forced-escalation child returned `ESCALATION_REQUIRED`; the root stopped,
  requested explicit approval, and completed only after a new approval turn.

The suite produced exactly one SOL root and three direct Terra High children,
with no grandchildren.

### Desktop dedicated-project canary

A disposable `SOL Ultra Tasks`-style folder was installed in project mode and
started through the bundled Desktop `0.144.0-alpha.4` app-server backend:

- the trusted fresh root recorded `gpt-5.6-sol` with `ultra` reasoning and the
  installed SOL Ultra policy in its rollout;
- its one non-full default child recorded `gpt-5.6-terra` with `high` reasoning;
- child and parent completion markers returned, and both threads were archived.

This validates the Desktop backend's new-task configuration and child routing.
An untrusted attempt correctly emitted the documented config-disabled warning,
but child routing was still observed and therefore was not used as a negative
control. The Projects-view add/open-and-trust UI step was not automated; it
remains the normal user-controlled activation sequence described in the
official Desktop project flow.

## Uninstall

The one-prompt form is:

```text
Uninstall this release v0.3.1 from the Codex surface and project this task started in, using the recorded managed-guidance state and without touching unrelated settings: https://github.com/carltonawong/sol-ultra-workaround
```

Profile mode:

```powershell
./uninstall.ps1
```

```sh
./uninstall.sh
```

Project mode:

```powershell
./uninstall.ps1 -Mode project -ProjectRoot C:\path\to\project
```

```sh
./uninstall.sh project /path/to/project
```

Uninstall verifies both TOML payloads and, in project mode, the installed
guidance copy plus the managed-root-guidance state against hashes recorded in
the local manifest. It refuses when state is missing or invalid, a payload hash
does not match, or the installation is incomplete. Existing installations must
first be uninstalled; v0.3.1 does not perform an in-place upgrade. The
manifest is not a signature and does not defend
against coordinated local edits. Schema-2 project uninstall restores its exact
recorded backup when the active guidance is otherwise unchanged; otherwise it
removes only the intact marked block and package files. It never removes or
restores unrelated Codex settings. On Windows, when the installer originally
created `AGENTS.md`, the race-safe PowerShell uninstaller may leave that file
present but empty instead of deleting it; it never leaves the managed block.

## Security and privacy

The installers:

- profile mode copies only the two TOML payloads and creates its local hash
  manifest;
- project mode also copies the managed guidance payload and changes only the
  selected active root guidance file within the exact managed markers (with a
  recorded backup when that file existed);
- refuse existing target files rather than overwrite them;
- make no network request;
- do not read or copy `auth.json`, credentials, sessions, telemetry, browser
  data, or account data;
- do not change sandbox, approval, MCP, plugin, or permission settings;
- require no administrator or root privileges.

Normal Codex model traffic continues. Spawned children inherit the root's
sandbox, tools, and permissions unless the user restricts them further.

## Limitations

- The final profile was tested end to end on the target SOL Ultra/V2 path with
  Codex CLI 0.144.0: the root recorded SOL Ultra, the non-full default child
  recorded Terra High, and the canary task passed. The V1 field is a fallback
  for a legacy schema, not a separately proven SOL Ultra lane.
- Desktop/IDE project configuration uses the same documented config layer, but
  the profile selector is CLI only. The bundled Desktop backend verified during
  development was 0.144.0-alpha.4.
- A top-level projectless Desktop task does not load the workaround. The folder
  must be added or opened and trusted as a Local Project, and the task must be
  created inside that project.
- This is an opt-in profile or directory scope, not a parent-model predicate.
- Switching models after launch does not automatically disable the declared
  child role.
- Project-local config has higher precedence than a CLI profile and can replace
  the profile's agent declaration.
- The approval gate, semantic handoff, root-only spawning, single-turn child
  lifecycle, and runtime result validation are model-followed policy. Hooks
  cannot enforce internal spawns or completed-child follow-ups.
- A failed Terra attempt followed by an approved SOL Ultra takeover can cost
  more than doing that task once on SOL; the stop exists so the user chooses.
- Exact five-hour allowance savings remain unobservable from local traces.
- Codex updates do not disable these files automatically. On an unverified
  version, stop using or uninstall the workaround until it is revalidated.
- Custom-agent authoring and SOL's reserved spawn schema may change in later
  Codex versions.

## Status

Temporary workaround. Remove it when Codex exposes supported per-spawn model,
reasoning, tier, context, and budget controls.
