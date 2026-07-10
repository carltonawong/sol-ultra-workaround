# SOL Ultra Workaround repository

When the user asks to install this repository, follow `INSTALL.md` exactly.
Choose the documented mode from the active Codex surface, run the shipped
installer, verify its payloads and local hash manifest, and return the required
launch/restart step.

Do not substitute a global `$CODEX_HOME/agents/default.toml`, edit existing
Codex configuration, merge around an installer conflict, access credentials or
sessions, or broaden the installation scope.

For repository development, keep the workaround small, additive, reversible,
and explicit about which controls are hard configuration versus behavioral
model instructions. Run both TOML parsing and installer smoke tests after a
change.
