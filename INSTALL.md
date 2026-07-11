# Installation contract for Codex

This file is written for a Codex agent asked to install this repository.

## Goal

Install the SOL Ultra Workaround for the Codex surface and project where the
request started, with the narrowest supported scope. Automatically target a
safe, unambiguous project. When a Desktop task is projectless, offer one safe
dedicated local project instead of requiring the user to invent a path. The
remaining user action is either launching with the named CLI profile or
opening/trusting the configured local project and starting a task inside it.

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
- Before downloading or entering the package checkout, record the original
  task surface, current directory, and app-declared workspace root(s). Keep
  using that recorded location for every target decision. Never infer the
  target from the temporary package checkout or the installer's working
  directory.
- Use the immutable `v0.2.2` release, not a moving branch. If an exact, clean
  `v0.2.2` checkout is not already available, clone it with
  `git clone --depth 1 --branch v0.2.2 https://github.com/carltonawong/sol-ultra-workaround.git`
  into a new temporary directory outside the original task workspace. Do not
  switch, clean, or otherwise modify a checkout that existed before the
  request, and do not pipe remote content directly into a shell.

## Check the version

For CLI, run `codex --version`. For Desktop/IDE, inspect the active bundled
backend version; do not substitute an unrelated CLI binary. Continue
automatically only for `0.144.0` or the verified Desktop build
`0.144.0-alpha.4`. If the active version cannot be determined or is different,
stop and ask whether the user wants to try an unverified version.

## Choose the mode and destination

Never run an installer until both the mode and any project destination are
explicit. Never fall back from an ambiguous Desktop/IDE target to CLI profile
mode.

1. **Codex CLI:** automatically choose `profile`. In profile mode, stop if the
   original project has a project-local `.codex/config.toml` distinct from the
   base `$CODEX_HOME/config.toml`; project configuration has higher precedence
   and can defeat the profile.
2. **Codex Desktop or IDE, one safe workspace root:** automatically choose
   `project` and pass that original root as an absolute `ProjectRoot`. A safe
   automatic target is one app-declared, dedicated project root that is not a
   filesystem root, the user's home, `$CODEX_HOME`, a broad directory holding
   multiple unrelated projects, or the downloaded package checkout.
3. **Codex Desktop, projectless task or unsafe/ambiguous root:** do not treat a
   top-level **New task** as an activation mechanism. Ask exactly:

   > This Desktop task has no safe local project. A top-level New task cannot
   > load SOL Ultra Workaround. Reply CREATE DEDICATED PROJECT to configure
   > `<home>/SOL Ultra Tasks`, reply with an absolute existing project folder,
   > or say CANCEL.

   A structured choice UI may be used when the client exposes one, but the
   plain-text question must always work.
4. **`CREATE DEDICATED PROJECT`:** resolve `<home>/SOL Ultra Tasks` for the
   current operating system. Create that directory only because the user chose
   this explicit option. If it already exists and is non-empty, redirected, or
   contains any `.codex` target, do not reuse, merge, clean, or delete it; ask
   for another absolute path. After a safe creation, use `project` mode there.
   Never edit the user's base config to mark it trusted. Report the normal
   Desktop step: add or open the folder as a Local Project, trust it, and use
   **New task** from inside that project.
5. **Codex IDE, unsafe or ambiguous root:** ask exactly:

   > This IDE task has no single safe workspace root. Which absolute folder or
   > workspace root should I configure? Reply with a path, or say CANCEL.

   Validate the answer under the same safety rules. Do not create a general
   Desktop-style project unless the user explicitly requests one.
6. **Unknown surface:** ask exactly: `Are you using Codex CLI, Desktop, or the
   IDE extension?` Then apply the matching rule above.
7. An existing `.codex/config.toml` or `.codex/agents/default.toml` is a hard
   conflict. Do not merge or overwrite it. Explain the exact conflicting path
   and ask for a different dedicated project only if that would still satisfy
   the user's request.

## Run

Windows, CLI:

```powershell
./install.ps1 -Mode profile
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
- Desktop project mode: say to add or open the folder as a trusted Local
  Project and create **New task** inside it; make clear that a top-level
  projectless **New task** will not load the workaround;
- IDE project mode: say to open and trust the configured folder, then start a
  fresh task there;
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
