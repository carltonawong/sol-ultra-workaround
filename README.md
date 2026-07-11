# SOL Ultra Workaround

An experimental, reversible Codex 0.144 workaround for keeping SOL Ultra
subagent use more predictable.

It gives an opt-in SOL Ultra root a Terra High default child, asks the root to
keep delegation to three active children (four distinct children per turn at
most), and asks it to send concise semantic handoffs instead of full-history
forks.

This is an unofficial configuration workaround, not a billing boundary or an
OpenAI-supported quota control.

## One-prompt install

Send this one line from the Codex task you want to configure:

```text
Install this release v0.2.2 for the Codex surface and project this task started in: https://github.com/carltonawong/sol-ultra-workaround
```

The install contract directs Codex to pin `v0.2.2`, read
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
rollouts were audited:

| Recorded child activity | Result |
| --- | ---: |
| Children | 39 |
| Model and reasoning | 39 x `gpt-5.6-sol`, `ultra` |
| Cumulative input tokens | 4,860,010,375 |
| Cached input tokens | 4,748,019,200 (97.7%) |
| Output tokens | 13,563,958 |

At the published rate-card ratio, the same token mix on Terra would consume
50% fewer child credits. That is a model-only inference, not a replay: Terra may
use a different number of tokens, and Codex does not expose an exact conversion
from a task trace to the five-hour allowance.

This reduces inherited starting context, but its net token savings have not
been isolated as a single percentage. The potential benefit grows with the
size of the parent task and number of children. The SOL Ultra root still
consumes SOL Ultra usage, and each child still carries its own system, tool,
skill, and growing task context.

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

The installed footprint is two TOML files plus a tiny local hash manifest,
totaling less than 4 KB. Nothing runs in the background after installation.

Codex 0.144 has no supported runtime condition meaning "apply this default
agent only if the current parent is SOL Ultra." Profiles provide opt-in CLI
scoping; project configuration provides directory scoping for Desktop/IDE.

### Why there is no "SOL Ultra selected" pop-up

Codex loads profile and project configuration when a task starts. A lifecycle
hook can inspect the active model and show a warning, but there is no
model-selection event, the hook does not receive the reasoning effort needed to
distinguish Ultra from High or Medium, and it cannot load a CLI profile or
replace the already-loaded task configuration. It would also require a global
script and hook-trust prompt affecting unrelated tasks. This package therefore
installs no hook, watcher, daemon, or global `AGENTS.md` rule. CLI activation
stays explicit; Desktop/IDE activation stays project-local.

## Install

The installers refuse to overwrite any existing file. Because the workaround
does not modify the user's base `config.toml`, global `AGENTS.md`, or global
`agents/default.toml`, uninstall does not need to restore them.

Codex still needs normal permission to clone/read the repository and write the
three new target files. The installer performs no network request itself.

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
only:

```text
<project>/.codex/config.toml
<project>/.codex/sol-ultra-workaround/terra-high.toml
<project>/.codex/sol-ultra-workaround/install-state.txt
```

Desktop: add or open the folder as a trusted Local Project, then create a fresh
task inside that project. IDE: open and trust the configured folder or
workspace, then start a fresh task there. If Codex 0.144 does not pick up a
project layer installed while the client was already open, fully restart the
client and try the fresh task again.

## Existing tasks

New tasks are the safest choice on Codex 0.144 because the complete profile
policy is guaranteed to load at task creation.

Existing tasks can still use the routing change:

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
V2 child fork:     fork_turns="none" (last 3 only with an explanation)
V1 child fork:     fork_context=false
V2 concurrency:   built-in root plus three active children
policy ceiling:   three active; four distinct children per user turn
nesting:          V1 depth one; V2 no-grandchildren policy is behavioral
```

Mechanical controls and runtime limits:

- the declared `default` role's Terra High model and reasoning on a compliant
  non-full default-role spawn;
- V2's built-in four active slots include the root, leaving three active child
  slots by default, unless another managed setting overrides that default;
- `max_depth=1` prevents V1 grandchildren. Codex 0.144 V2 ignores that setting.

Behavioral instructions, not mechanically enforced (only selected behaviors
below were exercised in scenarios):

- choosing the correct non-full fork field for V1 or V2;
- building the semantic handoff;
- keeping V1 to three active children;
- no more than four distinct children per user turn;
- preventing grandchildren under V2;
- stopping for approval before SOL Ultra root takeover.

Important: in Codex 0.144, a full-history spawn bypasses the custom role layer.
The Terra routing therefore depends on the root following the non-full-fork
instruction.

## Validation

Installer and routing-suite tests used disposable Codex homes. The Desktop
canary below used a disposable project with the live Desktop backend and
archived its test threads. A test-only attempt to supply trust through the
app-server persisted one dummy trust entry; cleanup removed that exact entry
and revalidated the base config. The released installer never writes trust or
edits the base config.

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
Uninstall this from the Codex surface and project this task started in without touching unrelated settings: https://github.com/carltonawong/sol-ultra-workaround (use release v0.2.2)
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

Uninstall verifies both TOML payloads against hashes recorded in the local
manifest. It refuses when state is missing or invalid, a payload hash does not
match, or the installation is incomplete. The manifest is not a signature and
does not defend against coordinated local edits. The original checkout and
payload version are not needed, but an uninstaller supporting manifest schema
1 is still required. It never removes or restores unrelated Codex settings.

## Security and privacy

The installers:

- copy only the two TOML payloads and create their local hash manifest;
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
- The approval gate and semantic handoff are model-followed policy.
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
