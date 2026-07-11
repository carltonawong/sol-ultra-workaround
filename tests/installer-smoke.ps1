[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Read-State([string]$Path) {
    $state = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) { $state[$parts[0]] = $parts[1] }
    }
    return $state
}

function File-Hash([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Wait-ForPath([string]$Path, [int]$Seconds = 15) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while (-not (Test-Path -LiteralPath $Path)) {
        if ([DateTime]::UtcNow -ge $deadline) { throw "Timed out waiting for: $Path" }
        Start-Sleep -Milliseconds 25
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$install = Join-Path $repoRoot "install.ps1"
$uninstall = Join-Path $repoRoot "uninstall.ps1"
$sourceConfig = Join-Path $repoRoot "profiles\sol-ultra.config.toml"
$sourceAgent = Join-Path $repoRoot "agents\terra-high.toml"
$sourceGuidance = Join-Path $repoRoot "profiles\sol-ultra.AGENTS.md"
$configText = [IO.File]::ReadAllText($sourceConfig)
$agentText = [IO.File]::ReadAllText($sourceAgent)
$guidanceText = [IO.File]::ReadAllText($sourceGuidance)
Assert-True ($configText.Contains('fork_turns="none"')) "config must require an isolated V2 fork"
Assert-True (-not $configText.Contains('fork_turns="all"')) "config permits full-history V2 forks"
Assert-True ($guidanceText.Contains('Only the active root may spawn')) "root-only spawn policy missing"
Assert-True ($guidanceText.Contains('A child''s self-report is not evidence')) "root runtime check missing"
Assert-True ($configText.Contains('Never call followup_task')) "config permits completed-child reuse"
Assert-True ($guidanceText.Contains('Never call `followup_task`')) "guidance permits completed-child reuse"
Assert-True ($guidanceText.Contains('exactly one triggered child turn')) "root single-turn verification missing"
Assert-True ($agentText.Contains('CODEX_THREAD_ID')) "child rollout discovery recipe missing"
Assert-True ($agentText.Contains('RUNTIME_OK model=gpt-5.6-terra effort=high isolated=true')) "success contract missing"
Assert-True ($agentText.Contains('ROUTING_FAILURE')) "failure contract missing"
Assert-True ($agentText.Contains('reason=completed_child_reuse')) "child reuse failure contract missing"
Assert-True ($agentText.Contains('exactly one inter_agent_communication_metadata event')) "child single-turn verification missing"
Assert-True (-not $agentText.Contains('RUNTIME_UNVERIFIED')) "runtime contract has a third state"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "sol-ultra-smoke-" + [Guid]::NewGuid().ToString("N")
)
$oldCodexHome = $env:CODEX_HOME

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    # Profile mode remains isolated from every AGENTS file.
    $profileHome = Join-Path $testRoot "profile-home"
    New-Item -ItemType Directory -Path $profileHome | Out-Null
    $env:CODEX_HOME = $profileHome
    & $install -Mode profile | Out-Null
    $profileStatePath = Join-Path $profileHome "sol-ultra-workaround\install-state.txt"
    $profileState = Read-State $profileStatePath
    Assert-True ($profileState.schema -eq "2") "profile install should write schema 2"
    Assert-True ($profileState.guidance_action -eq "none") "profile mode must not manage guidance"
    Assert-True (-not (Test-Path (Join-Path $profileHome "AGENTS.md"))) "profile mode created global AGENTS.md"
    & $uninstall -Mode profile | Out-Null
    Assert-True (-not (Test-Path (Join-Path $profileHome "sol-ultra.config.toml"))) "profile config remained"

    # Existing AGENTS.md is backed up byte-for-byte. Later user edits survive uninstall.
    $existingProject = Join-Path $testRoot "existing-project"
    New-Item -ItemType Directory -Path $existingProject | Out-Null
    $existingGuidance = Join-Path $existingProject "AGENTS.md"
    $originalBytes = [Text.UTF8Encoding]::new($false).GetBytes("# Existing guidance`r`n`r`nKeep this.`r`n")
    [IO.File]::WriteAllBytes($existingGuidance, $originalBytes)
    & $install -Mode project -ProjectRoot $existingProject | Out-Null
    $backup = Join-Path $existingProject ".codex\sol-ultra-workaround\AGENTS.md.preinstall.bak"
    $installedBlock = Join-Path $existingProject ".codex\sol-ultra-workaround\guidance-block.md"
    Assert-True (Test-Path $backup) "existing guidance backup missing"
    Assert-True ((File-Hash $installedBlock) -eq
        (File-Hash $sourceGuidance)) "installed guidance block differs from source"
    Assert-True ((File-Hash $backup) -eq (File-Hash $existingGuidance) -or
        ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -eq
         [Convert]::ToBase64String($originalBytes))) "backup did not preserve original bytes"
    [IO.File]::AppendAllText($existingGuidance, "`nUSER_EDIT_AFTER_INSTALL`n", [Text.UTF8Encoding]::new($false))
    & $uninstall -Mode project -ProjectRoot $existingProject | Out-Null
    $remaining = [IO.File]::ReadAllText($existingGuidance)
    Assert-True ($remaining.Contains("# Existing guidance")) "original guidance was lost"
    Assert-True ($remaining.Contains("USER_EDIT_AFTER_INSTALL")) "later user edit was lost"
    Assert-True (-not $remaining.Contains("SOL-ULTRA-WORKAROUND:BEGIN")) "managed block remained"

    # An installer-created AGENTS.md loses the managed block when unchanged.
    # PowerShell may retain a zero-byte file to avoid a delete race.
    $createdProject = Join-Path $testRoot "created-project"
    New-Item -ItemType Directory -Path $createdProject | Out-Null
    & $install -Mode project -ProjectRoot $createdProject | Out-Null
    Assert-True (Test-Path (Join-Path $createdProject "AGENTS.md")) "project guidance was not created"
    & $uninstall -Mode project -ProjectRoot $createdProject | Out-Null
    $createdGuidance = Join-Path $createdProject "AGENTS.md"
    Assert-True ((-not (Test-Path $createdGuidance)) -or
        ((Get-Item -LiteralPath $createdGuidance).Length -eq 0)) "created guidance retained managed content"

    # AGENTS.override.md is the active file and must be selected without touching AGENTS.md.
    $overrideProject = Join-Path $testRoot "override-project"
    New-Item -ItemType Directory -Path $overrideProject | Out-Null
    $normalGuidance = Join-Path $overrideProject "AGENTS.md"
    $overrideGuidance = Join-Path $overrideProject "AGENTS.override.md"
    [IO.File]::WriteAllText($normalGuidance, "NORMAL_ONLY`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($overrideGuidance, "OVERRIDE_ONLY`n", [Text.UTF8Encoding]::new($false))
    $normalBefore = File-Hash $normalGuidance
    & $install -Mode project -ProjectRoot $overrideProject | Out-Null
    Assert-True ((File-Hash $normalGuidance) -eq $normalBefore) "inactive AGENTS.md was modified"
    Assert-True (([IO.File]::ReadAllText($overrideGuidance)).Contains("SOL-ULTRA-WORKAROUND:BEGIN")) "override was not managed"
    & $uninstall -Mode project -ProjectRoot $overrideProject | Out-Null
    Assert-True (([IO.File]::ReadAllText($overrideGuidance)) -eq "OVERRIDE_ONLY`n") "override was not restored exactly"
    Assert-True ((File-Hash $normalGuidance) -eq $normalBefore) "normal guidance changed during uninstall"

    # Pre-existing managed markers are a conflict; no package file may be added.
    $markerProject = Join-Path $testRoot "marker-project"
    New-Item -ItemType Directory -Path $markerProject | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $markerProject "AGENTS.md"),
        "user text <!-- SOL-ULTRA-WORKAROUND:BEGIN --> malformed`n",
        [Text.UTF8Encoding]::new($false)
    )
    $markerFailed = $false
    try { & $install -Mode project -ProjectRoot $markerProject | Out-Null } catch { $markerFailed = $true }
    Assert-True $markerFailed "pre-existing marker did not stop install"
    Assert-True (-not (Test-Path (Join-Path $markerProject ".codex\config.toml"))) "marker conflict left config"

    # NUL-containing guidance is binary and must never be rewritten.
    $binaryProject = Join-Path $testRoot "binary-project"
    New-Item -ItemType Directory -Path $binaryProject | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $binaryProject "AGENTS.md"), [byte[]](0x75, 0x73, 0x65, 0x72, 0x00, 0x64, 0x61, 0x74, 0x61))
    $binaryFailed = $false
    try { & $install -Mode project -ProjectRoot $binaryProject | Out-Null } catch { $binaryFailed = $true }
    Assert-True $binaryFailed "binary guidance did not stop install"
    Assert-True (-not (Test-Path (Join-Path $binaryProject ".codex\config.toml"))) "binary conflict left config"

    # A changed managed block is a hard stop and must leave every owned file in place.
    $tamperProject = Join-Path $testRoot "tamper-project"
    New-Item -ItemType Directory -Path $tamperProject | Out-Null
    [IO.File]::WriteAllText((Join-Path $tamperProject "AGENTS.md"), "ORIGINAL`n", [Text.UTF8Encoding]::new($false))
    & $install -Mode project -ProjectRoot $tamperProject | Out-Null
    $tamperGuidance = Join-Path $tamperProject "AGENTS.md"
    $tampered = ([IO.File]::ReadAllText($tamperGuidance)).Replace(
        "Only the active root may spawn", "Only a changed root may spawn"
    )
    [IO.File]::WriteAllText($tamperGuidance, $tampered, [Text.UTF8Encoding]::new($false))
    $tamperConfig = Join-Path $tamperProject ".codex\config.toml"
    $tamperHash = File-Hash $tamperConfig
    $failed = $false
    try { & $uninstall -Mode project -ProjectRoot $tamperProject | Out-Null } catch { $failed = $true }
    Assert-True $failed "tampered managed block did not stop uninstall"
    Assert-True ((File-Hash $tamperConfig) -eq $tamperHash) "failed uninstall changed owned config"
    Assert-True (Test-Path (Join-Path $tamperProject ".codex\sol-ultra-workaround\install-state.txt")) "failed uninstall removed state"

    # A changed backup is also a hard stop.
    $backupTamperProject = Join-Path $testRoot "backup-tamper-project"
    New-Item -ItemType Directory -Path $backupTamperProject | Out-Null
    [IO.File]::WriteAllText((Join-Path $backupTamperProject "AGENTS.md"), "KEEP_ME`n", [Text.UTF8Encoding]::new($false))
    & $install -Mode project -ProjectRoot $backupTamperProject | Out-Null
    $backupTamperPath = Join-Path $backupTamperProject ".codex\sol-ultra-workaround\AGENTS.md.preinstall.bak"
    [IO.File]::AppendAllText($backupTamperPath, "tamper", [Text.UTF8Encoding]::new($false))
    $backupFailed = $false
    try { & $uninstall -Mode project -ProjectRoot $backupTamperProject | Out-Null } catch { $backupFailed = $true }
    Assert-True $backupFailed "tampered backup did not stop uninstall"
    Assert-True (Test-Path (Join-Path $backupTamperProject ".codex\config.toml")) "backup failure removed config"

    # A save after installer validation must not be overwritten by rollback.
    $raceInstallProject = Join-Path $testRoot "race-install-project"
    $raceInstallHome = Join-Path $testRoot "race-install-home"
    New-Item -ItemType Directory -Path $raceInstallProject,$raceInstallHome | Out-Null
    $raceInstallGuidance = Join-Path $raceInstallProject "AGENTS.md"
    [IO.File]::WriteAllText($raceInstallGuidance, "RACE_ORIGINAL`n", [Text.UTF8Encoding]::new($false))
    $raceInstallSignal = Join-Path $testRoot "race-install-signal"
    $env:CODEX_HOME = $raceInstallHome
    $env:SOL_ULTRA_WORKAROUND_TEST_PAUSE = "install-after-guidance"
    $env:SOL_ULTRA_WORKAROUND_TEST_SIGNAL = $raceInstallSignal
    $powershellExe = (Get-Process -Id $PID).Path
    $raceInstallArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$install`" -Mode project -ProjectRoot `"$raceInstallProject`""
    $raceInstallProcess = Start-Process -FilePath $powershellExe -ArgumentList $raceInstallArgs -PassThru -WindowStyle Hidden
    Wait-ForPath ($raceInstallSignal + ".ready")
    [IO.File]::AppendAllText($raceInstallGuidance, "RACE_USER_EDIT`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText(
        (Join-Path $raceInstallProject ".codex\sol-ultra-workaround\install-state.txt"),
        "collision",
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText($raceInstallSignal + ".continue", "go", [Text.UTF8Encoding]::new($false))
    $raceInstallProcess.WaitForExit()
    Assert-True ($raceInstallProcess.ExitCode -ne 0) "forced installer rollback unexpectedly succeeded"
    Assert-True (([IO.File]::ReadAllText($raceInstallGuidance)).Contains("RACE_USER_EDIT")) "installer rollback lost concurrent edit"
    Assert-True (Test-Path (Join-Path $raceInstallProject ".codex\sol-ultra-workaround\AGENTS.md.preinstall.bak")) "unsafe rollback removed recovery backup"

    # Uninstall must re-read an edit made after its initial validation.
    $raceUninstallProject = Join-Path $testRoot "race-uninstall-project"
    $raceUninstallHome = Join-Path $testRoot "race-uninstall-home"
    New-Item -ItemType Directory -Path $raceUninstallProject,$raceUninstallHome | Out-Null
    $raceUninstallGuidance = Join-Path $raceUninstallProject "AGENTS.md"
    [IO.File]::WriteAllText($raceUninstallGuidance, "UNINSTALL_ORIGINAL`n", [Text.UTF8Encoding]::new($false))
    $env:CODEX_HOME = $raceUninstallHome
    Remove-Item Env:SOL_ULTRA_WORKAROUND_TEST_PAUSE -ErrorAction SilentlyContinue
    Remove-Item Env:SOL_ULTRA_WORKAROUND_TEST_SIGNAL -ErrorAction SilentlyContinue
    & $install -Mode project -ProjectRoot $raceUninstallProject | Out-Null
    $raceUninstallSignal = Join-Path $testRoot "race-uninstall-signal"
    $env:SOL_ULTRA_WORKAROUND_TEST_PAUSE = "uninstall-before-guidance-mutation"
    $env:SOL_ULTRA_WORKAROUND_TEST_SIGNAL = $raceUninstallSignal
    $raceUninstallArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$uninstall`" -Mode project -ProjectRoot `"$raceUninstallProject`""
    $raceUninstallProcess = Start-Process -FilePath $powershellExe -ArgumentList $raceUninstallArgs -PassThru -WindowStyle Hidden
    Wait-ForPath ($raceUninstallSignal + ".ready")
    [IO.File]::AppendAllText($raceUninstallGuidance, "UNINSTALL_RACE_EDIT`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($raceUninstallSignal + ".continue", "go", [Text.UTF8Encoding]::new($false))
    $raceUninstallProcess.WaitForExit()
    Assert-True ($raceUninstallProcess.ExitCode -eq 0) "race-aware uninstall failed"
    $raceUninstallRemaining = [IO.File]::ReadAllText($raceUninstallGuidance)
    Assert-True ($raceUninstallRemaining.Contains("UNINSTALL_RACE_EDIT")) "uninstall lost concurrent edit"
    Assert-True (-not $raceUninstallRemaining.Contains("SOL-ULTRA-WORKAROUND:BEGIN")) "uninstall race left managed block"

    Remove-Item Env:SOL_ULTRA_WORKAROUND_TEST_PAUSE -ErrorAction SilentlyContinue
    Remove-Item Env:SOL_ULTRA_WORKAROUND_TEST_SIGNAL -ErrorAction SilentlyContinue

    # The new uninstaller remains able to remove a complete schema-1 profile install.
    $legacyHome = Join-Path $testRoot "legacy-home"
    $legacyAgentDir = Join-Path $legacyHome "sol-ultra-workaround"
    New-Item -ItemType Directory -Path $legacyAgentDir -Force | Out-Null
    $legacyConfig = Join-Path $legacyHome "sol-ultra.config.toml"
    $legacyAgent = Join-Path $legacyAgentDir "terra-high.toml"
    Copy-Item -LiteralPath $sourceConfig -Destination $legacyConfig
    Copy-Item -LiteralPath $sourceAgent -Destination $legacyAgent
    $legacyState = "schema=1`nmode=profile`nconfig_sha256=$(File-Hash $legacyConfig)`nagent_sha256=$(File-Hash $legacyAgent)`nconfig_parent_created=0`nagent_parent_created=1`n"
    [IO.File]::WriteAllText((Join-Path $legacyAgentDir "install-state.txt"), $legacyState, [Text.UTF8Encoding]::new($false))
    $env:CODEX_HOME = $legacyHome
    & $uninstall -Mode profile | Out-Null
    Assert-True (-not (Test-Path $legacyConfig)) "schema-1 config remained"
    Assert-True (-not (Test-Path $legacyAgent)) "schema-1 agent remained"

    # Schema-1 project installs remain removable without touching root guidance.
    $legacyProject = Join-Path $testRoot "legacy-project"
    $legacyProjectAgentDir = Join-Path $legacyProject ".codex\sol-ultra-workaround"
    New-Item -ItemType Directory -Path $legacyProjectAgentDir -Force | Out-Null
    $legacyProjectConfig = Join-Path $legacyProject ".codex\config.toml"
    $legacyProjectAgent = Join-Path $legacyProjectAgentDir "terra-high.toml"
    $legacyProjectGuidance = Join-Path $legacyProject "AGENTS.md"
    [IO.File]::WriteAllText($legacyProjectGuidance, "LEGACY_GUIDANCE`n", [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $sourceConfig -Destination $legacyProjectConfig
    Copy-Item -LiteralPath $sourceAgent -Destination $legacyProjectAgent
    $legacyProjectState = "schema=1`nmode=project`nconfig_sha256=$(File-Hash $legacyProjectConfig)`nagent_sha256=$(File-Hash $legacyProjectAgent)`nconfig_parent_created=1`nagent_parent_created=1`n"
    [IO.File]::WriteAllText((Join-Path $legacyProjectAgentDir "install-state.txt"), $legacyProjectState, [Text.UTF8Encoding]::new($false))
    & $uninstall -Mode project -ProjectRoot $legacyProject | Out-Null
    Assert-True (-not (Test-Path $legacyProjectConfig)) "schema-1 project config remained"
    Assert-True (([IO.File]::ReadAllText($legacyProjectGuidance)) -eq "LEGACY_GUIDANCE`n") "schema-1 uninstall changed guidance"

    Write-Host "PowerShell installer smoke tests passed."
} finally {
    $env:CODEX_HOME = $oldCodexHome
    Remove-Item Env:SOL_ULTRA_WORKAROUND_TEST_PAUSE -ErrorAction SilentlyContinue
    Remove-Item Env:SOL_ULTRA_WORKAROUND_TEST_SIGNAL -ErrorAction SilentlyContinue
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedTest = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTest).StartsWith("sol-ultra-smoke-")) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force -ErrorAction SilentlyContinue
    }
}
