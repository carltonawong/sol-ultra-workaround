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

Do not substitute a global `$CODEX_HOME/agents/default.toml`, edit existing
Codex configuration, merge around an installer conflict, access credentials or
sessions, or broaden the installation scope.

For repository development, keep the workaround small, additive, reversible,
and explicit about which controls are hard configuration versus behavioral
model instructions. Run both TOML parsing and installer smoke tests after a
change.
