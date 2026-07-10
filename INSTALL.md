# Installation contract for Codex

This file is written for a Codex agent asked to install this repository.

## Goal

Install the SOL Ultra Workaround for the user's current Codex surface with the
narrowest supported scope. The user should need only one action after the
agent finishes: either launch with the named profile or restart/open the
configured project.

## Safety rules

- Read `README.md` before changing anything.
- Never copy a package file into `$CODEX_HOME/agents/`.
- Never edit or overwrite the user's base `config.toml`, global `AGENTS.md`,
  global `AGENTS.override.md`, credentials, auth files, sessions, plugins,
  sandbox settings, approval settings, or telemetry settings.
- Never use administrator/root privileges.
- Run only the installer shipped in this repository.
- Stop on an existing target, partial installation, modified installed file,
  or other conflict. Do not improvise a merge.
- Before downloading or entering the package checkout, remember the original
  task workspace. Never use the package checkout itself as the project target.
- If the repository is not already available, clone the pinned release with
  `git clone --depth 1 --branch v0.2.0 https://github.com/carltonawong/sol-ultra-workaround.git`
  into a new temporary directory outside the original task workspace. Do not
  pipe remote content directly into a shell.

## Check the version

For CLI, run `codex --version`. For Desktop/IDE, inspect the active bundled
backend version; do not substitute an unrelated CLI binary. Continue
automatically only for `0.144.0` or the verified Desktop build
`0.144.0-alpha.4`. If the active version cannot be determined or is different,
stop and ask whether the user wants to try an unverified version.

## Choose the mode

1. If the current surface is Codex CLI, use `profile`.
2. If the current surface is Codex Desktop or the IDE extension, use `project`
   for the original trusted task project, not the downloaded package checkout.
3. If the surface cannot be determined, ask one short question rather than
   guessing.
4. If there is not exactly one clear original project root, ask one short
   question instead of guessing.
5. If Desktop/IDE is rooted at the user's home directory, or the project
   already has `.codex/config.toml` or `.codex/agents/default.toml`, stop and
   explain that Codex 0.144 cannot provide a parent-model-only global override.
   A dedicated project/new task is required for isolation.
6. In CLI profile mode, stop if the original project has a project-local
   `.codex/config.toml` distinct from the base `$CODEX_HOME/config.toml`.
   Project configuration has higher precedence and can defeat this profile.

## Run

Windows, CLI:

```powershell
./install.ps1
```

Windows, Desktop or IDE:

```powershell
./install.ps1 -Mode project -ProjectRoot "<absolute-project-root>"
```

macOS/Linux, CLI:

```sh
./install.sh profile
```

macOS/Linux, Desktop or IDE:

```sh
./install.sh project "<absolute-project-root>"
```

## Verify

Profile mode must add exactly:

```text
$CODEX_HOME/sol-ultra.config.toml
$CODEX_HOME/sol-ultra-workaround/terra-high.toml
$CODEX_HOME/sol-ultra-workaround/install-state.txt
```

Project mode must add exactly:

```text
<project>/.codex/config.toml
<project>/.codex/sol-ultra-workaround/terra-high.toml
<project>/.codex/sol-ultra-workaround/install-state.txt
```

Before installation, verify only that the three documented targets do not
exist. After installation, verify both TOML payloads are byte-identical to the
package sources and that the local manifest contains their SHA-256 hashes. Do
not hash, read, or print unrelated files from the user's Codex home.

## Report to the user

Keep the completion message short:

- state which mode was installed;
- confirm that no existing settings were overwritten;
- profile mode: say `codex --profile sol-ultra` for new tasks and
  `codex resume --profile sol-ultra <SESSION_ID_OR_NAME>` for an existing CLI
  task;
- project mode: say to fully quit/restart Codex and open that project;
- recommend a new task on Codex 0.144 for the complete policy to load reliably.

If this repository was cloned only for installation, remove the agent-created
temporary clone after successful verification when it is safe to do so. Do not
remove a checkout that existed before the request. The user can run the
one-prompt uninstall from the tagged repository later.

## Uninstall requests

When the user asks to uninstall, choose the same surface-specific mode, run the
shipped `uninstall.ps1` or `uninstall.sh`, and verify that only the three
manifest-owned targets were removed. The uninstaller must stop on invalid
state, hash mismatch, redirected paths, or a partial installation. Never repair
or delete those cases automatically.
