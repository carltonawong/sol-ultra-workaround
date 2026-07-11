# SOL Ultra Workaround repository

When the user asks to install this repository, follow `INSTALL.md` exactly.
Record the task's original surface and workspace before entering a temporary
clone. Choose CLI profile mode automatically. For Desktop/IDE, automatically
target the single original dedicated project when it is safe; otherwise ask
the surface-specific choice specified in `INSTALL.md`: Desktop may offer the
dedicated-project option, while IDE asks for one absolute folder/workspace root.
If the Desktop user selects `CREATE DEDICATED PROJECT`, create only the safe
`~/SOL Ultra Tasks` directory described there. Never silently fall back from
Desktop/IDE to profile mode or edit base config to mark a project trusted. Run
the shipped installer with an explicit mode, verify its payloads and local hash
manifest, and return the required activation step.

Do not substitute a global `$CODEX_HOME/agents/default.toml`, edit the base
Codex configuration, merge around an installer conflict, access credentials or
sessions, or broaden the installation scope. Project mode is the sole
exception for active root guidance: it may append this package's marked managed
block to the selected project's `AGENTS.override.md` when present, otherwise
`AGENTS.md`, preserving user content outside the markers and creating the
installer-managed backup when required. It must never edit global `AGENTS.md`
or `AGENTS.override.md`.

For repository development, keep the workaround small, additive, reversible,
and explicit about which controls are hard configuration versus behavioral
model instructions. The managed block must remain self-contained and use the
exact `SOL-ULTRA-WORKAROUND` markers. Do not claim hooks enforce internal
spawning: they cannot intercept `spawn_agent`. Run both TOML parsing and
installer smoke tests after a change.
