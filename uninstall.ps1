[CmdletBinding()]
param(
    [ValidateSet("profile", "project")]
    [string]$Mode = "profile",
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

function Assert-PlainDirectoryIfPresent([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    if (-not $item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "Refusing a non-directory, linked, or redirected target: $Path" }
}
function Assert-PlainFile([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "Refusing a missing, non-file, linked, or redirected target: $Path" }
}
function Assert-NoReparseAncestors([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -Force -LiteralPath $cursor -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0))) { throw "Refusing a path with a linked or redirected ancestor: $cursor" }
        $parent = Split-Path -Parent $cursor; if (-not $parent -or $parent -eq $cursor) { break }; $cursor = $parent
    }
}
function Get-Sha256([string]$Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Read-StreamBytes([IO.FileStream]$Stream) {
    $Stream.Position = 0
    $memory = [IO.MemoryStream]::new()
    try { $Stream.CopyTo($memory); return $memory.ToArray() }
    finally { $memory.Dispose() }
}
function Write-StreamBytes([IO.FileStream]$Stream, [byte[]]$Bytes) {
    $Stream.Position = 0; $Stream.SetLength(0)
    if ($Bytes.Length -gt 0) { $Stream.Write($Bytes, 0, $Bytes.Length) }
    $Stream.Flush()
}
function Invoke-TestPause([string]$Name) {
    if ($env:SOL_ULTRA_WORKAROUND_TEST_PAUSE -ne $Name) { return }
    $signal = $env:SOL_ULTRA_WORKAROUND_TEST_SIGNAL
    if ([string]::IsNullOrWhiteSpace($signal)) { throw "Test pause requires SOL_ULTRA_WORKAROUND_TEST_SIGNAL." }
    [IO.File]::WriteAllText($signal + ".ready", $Name, [Text.UTF8Encoding]::new($false))
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath ($signal + ".continue"))) {
        if ([DateTime]::UtcNow -ge $deadline) { throw "Timed out waiting for test pause continuation: $Name" }
        [Threading.Thread]::Sleep(25)
    }
}
function Remove-EmptyRecordedDirectory([string]$Path, [string]$CreatedFlag) {
    if ($CreatedFlag -eq "1" -and (Test-Path -LiteralPath $Path -PathType Container) -and -not (Get-ChildItem -Force -LiteralPath $Path | Select-Object -First 1)) { Remove-Item -Force -LiteralPath $Path }
}
function Read-State([string]$Path, [string[]]$AllowedKeys) {
    Assert-PlainFile $Path; $state = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2 -or $parts[0] -notin $AllowedKeys -or $state.ContainsKey($parts[0])) { throw "Invalid install state. Refusing to remove anything." }
        $state[$parts[0]] = $parts[1]
    }
    if ($state.Count -ne $AllowedKeys.Count) { throw "Invalid install state. Refusing to remove anything." }
    return $state
}
function Assert-GuidanceText([byte[]]$Bytes, [string]$Path) {
    if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe) -or ($Bytes[0] -eq 0xfe -and $Bytes[1] -eq 0xff))) { throw "Refusing UTF-16 guidance file: $Path" }
    if ($Bytes.Length -ge 4 -and (($Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe -and $Bytes[2] -eq 0 -and $Bytes[3] -eq 0) -or ($Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 0xfe -and $Bytes[3] -eq 0xff))) { throw "Refusing UTF-32 guidance file: $Path" }
    if ($Bytes -contains 0) { throw "Refusing clearly non-text guidance file: $Path" }
    try { [void]([Text.UTF8Encoding]::new($false, $true).GetString($Bytes)) } catch { throw "Refusing non-UTF-8 guidance file: $Path" }
}
function Find-ByteOccurrences([byte[]]$Haystack, [byte[]]$Needle) {
    $matches = [System.Collections.Generic.List[int]]::new()
    if ($Needle.Length -eq 0 -or $Needle.Length -gt $Haystack.Length) { return $matches }
    for ($i = 0; $i -le $Haystack.Length - $Needle.Length; $i++) {
        $same = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) { if ($Haystack[$i + $j] -ne $Needle[$j]) { $same = $false; break } }
        if ($same) { [void]$matches.Add($i) }
    }
    return $matches
}
function Remove-ByteRange([byte[]]$Bytes, [int]$Offset, [int]$Length) {
    $result = [byte[]]::new($Bytes.Length - $Length)
    if ($Offset -gt 0) { [Array]::Copy($Bytes, 0, $result, 0, $Offset) }
    $tail = $Bytes.Length - ($Offset + $Length)
    if ($tail -gt 0) { [Array]::Copy($Bytes, $Offset + $Length, $result, $Offset, $tail) }
    return $result
}
$packageRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$codexHome = if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME) } else { [IO.Path]::GetFullPath((Join-Path $HOME ".codex")) }
Assert-NoReparseAncestors $codexHome
if (Test-Path -LiteralPath $codexHome -PathType Container) { $codexHome = (Resolve-Path -LiteralPath $codexHome).Path }
if ($Mode -eq "profile") {
    $targetConfig = Join-Path $codexHome "sol-ultra.config.toml"; $targetAgent = Join-Path $codexHome "sol-ultra-workaround\terra-high.toml"
} else {
    if (-not [IO.Path]::IsPathRooted($ProjectRoot)) { throw "ProjectRoot must be an absolute path: $ProjectRoot" }
    $projectCandidate = [IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $projectCandidate -PathType Container)) { throw "Project root does not exist: $projectCandidate" }
    Assert-NoReparseAncestors $projectCandidate; $resolvedProject = (Resolve-Path -LiteralPath $projectCandidate).Path; $resolvedHome = (Resolve-Path -LiteralPath $HOME).Path
    if ($resolvedProject -ieq $resolvedHome) { throw "Refusing to treat the user's home directory as project mode." }
    if ($resolvedProject -ieq $packageRoot -and (Test-Path -LiteralPath (Join-Path $packageRoot "profiles\sol-ultra.config.toml"))) { throw "Refusing to treat the package checkout as project mode." }
    $projectCodexDir = Join-Path $resolvedProject ".codex"; Assert-PlainDirectoryIfPresent $projectCodexDir
    $targetConfig = [IO.Path]::GetFullPath((Join-Path $projectCodexDir "config.toml")); $baseConfig = [IO.Path]::GetFullPath((Join-Path $codexHome "config.toml"))
    if ($targetConfig -ieq $baseConfig) { throw "Refusing to treat the user's base Codex config as project mode." }
    $targetAgent = Join-Path $projectCodexDir "sol-ultra-workaround\terra-high.toml"
}

$configParent = Split-Path -Parent $targetConfig; $agentParent = Split-Path -Parent $targetAgent
Assert-PlainDirectoryIfPresent $configParent; Assert-PlainDirectoryIfPresent $agentParent
$targetState = Join-Path $agentParent "install-state.txt"
$present = @($targetConfig, $targetAgent, $targetState) | Where-Object { $null -ne (Get-Item -Force -LiteralPath $_ -ErrorAction SilentlyContinue) }
if ($present.Count -eq 0) { Write-Host "SOL Ultra Workaround is not installed in $Mode mode."; return }
if ($present.Count -ne 3) { throw "Partial installation detected. Refusing to remove anything." }
Assert-PlainFile $targetConfig; Assert-PlainFile $targetAgent; Assert-PlainFile $targetState

$commonKeys = @("schema", "mode", "config_sha256", "agent_sha256", "config_parent_created", "agent_parent_created")
$stateLines = Get-Content -LiteralPath $targetState
$schemaLine = @($stateLines | Where-Object { $_ -match '^schema=' })
if ($schemaLine.Count -ne 1) { throw "Invalid install state. Refusing to remove anything." }
$schema = $schemaLine[0].Substring(7)
if ($schema -eq "1") {
    $state = Read-State $targetState $commonKeys
    if ($state.mode -ne $Mode -or $state.config_sha256 -notmatch "^[0-9a-f]{64}$" -or $state.agent_sha256 -notmatch "^[0-9a-f]{64}$" -or $state.config_parent_created -notin @("0", "1") -or $state.agent_parent_created -notin @("0", "1")) { throw "Invalid install state. Refusing to remove anything." }
    $guidancePlan = $null
} elseif ($schema -eq "2") {
    $schema2Keys = $commonKeys + @("guidance_action", "guidance_file", "guidance_pre_sha256", "guidance_post_sha256", "guidance_backup_sha256", "guidance_block_sha256")
    $state = Read-State $targetState $schema2Keys
    if ($state.mode -ne $Mode -or $state.config_sha256 -notmatch "^[0-9a-f]{64}$" -or $state.agent_sha256 -notmatch "^[0-9a-f]{64}$" -or $state.config_parent_created -notin @("0", "1") -or $state.agent_parent_created -notin @("0", "1")) { throw "Invalid install state. Refusing to remove anything." }
    if ($Mode -eq "profile") {
        if ($state.guidance_action -ne "none" -or $state.guidance_file -ne "none" -or $state.guidance_pre_sha256 -ne "none" -or $state.guidance_post_sha256 -ne "none" -or $state.guidance_backup_sha256 -ne "none" -or $state.guidance_block_sha256 -ne "none") { throw "Invalid profile guidance state. Refusing to remove anything." }
        $guidancePlan = $null
    } else {
        if ($state.guidance_action -notin @("created", "appended") -or $state.guidance_file -notin @("AGENTS.md", "AGENTS.override.md") -or $state.guidance_post_sha256 -notmatch "^[0-9a-f]{64}$" -or $state.guidance_block_sha256 -notmatch "^[0-9a-f]{64}$") { throw "Invalid project guidance state. Refusing to remove anything." }
        $guidancePath = Join-Path $resolvedProject $state.guidance_file; $targetBlock = Join-Path $agentParent "guidance-block.md"; $targetBackup = Join-Path $agentParent ($state.guidance_file + ".preinstall.bak")
        Assert-PlainFile $guidancePath; Assert-PlainFile $targetBlock
        if ((Get-Sha256 $targetBlock) -ne $state.guidance_block_sha256) { throw "Managed guidance block hash does not match. Refusing to remove anything." }
        $blockBytes = [IO.File]::ReadAllBytes($targetBlock); Assert-GuidanceText $blockBytes $targetBlock
        $guidanceBytes = [IO.File]::ReadAllBytes($guidancePath); Assert-GuidanceText $guidanceBytes $guidancePath
        $guidanceText = [Text.UTF8Encoding]::new($false, $true).GetString($guidanceBytes)
        $beginMarker = "<!-- SOL-ULTRA-WORKAROUND:BEGIN -->"; $endMarker = "<!-- SOL-ULTRA-WORKAROUND:END -->"
        $markerCount = ([regex]::Matches($guidanceText, [regex]::Escape($beginMarker))).Count + ([regex]::Matches($guidanceText, [regex]::Escape($endMarker))).Count
        $occurrences = Find-ByteOccurrences $guidanceBytes $blockBytes
        if ($occurrences.Count -ne 1 -or $markerCount -ne 2) { throw "Managed guidance block is missing, changed, or duplicated. Refusing to remove anything." }
        if ($state.guidance_action -eq "created") {
            if ($state.guidance_pre_sha256 -ne "none" -or $state.guidance_backup_sha256 -ne "none") { throw "Invalid created-guidance state. Refusing to remove anything." }
            if ($null -ne (Get-Item -Force -LiteralPath $targetBackup -ErrorAction SilentlyContinue)) { throw "Unexpected guidance backup exists. Refusing to remove anything." }
        } else {
            if ($state.guidance_pre_sha256 -notmatch "^[0-9a-f]{64}$" -or $state.guidance_backup_sha256 -notmatch "^[0-9a-f]{64}$") { throw "Invalid appended-guidance state. Refusing to remove anything." }
            Assert-PlainFile $targetBackup
            if ((Get-Sha256 $targetBackup) -ne $state.guidance_backup_sha256 -or $state.guidance_backup_sha256 -ne $state.guidance_pre_sha256) { throw "Guidance backup hash does not match. Refusing to remove anything." }
        }
        $guidancePlan = [pscustomobject]@{ Path = $guidancePath; BlockPath = $targetBlock; BackupPath = $targetBackup; Action = $state.guidance_action; BlockBytes = $blockBytes }
    }
} else { throw "Unsupported install state schema. Refusing to remove anything." }

if ((Get-Sha256 $targetConfig) -ne $state.config_sha256) { throw "Installed config hash does not match. Refusing to delete it." }
if ((Get-Sha256 $targetAgent) -ne $state.agent_sha256) { throw "Installed agent hash does not match. Refusing to delete it." }

$suffix = ".sol-ultra-remove-" + [Guid]::NewGuid().ToString("N")
$pairs = @([pscustomobject]@{ Original = $targetConfig; Tombstone = $targetConfig + $suffix }, [pscustomobject]@{ Original = $targetAgent; Tombstone = $targetAgent + $suffix }, [pscustomobject]@{ Original = $targetState; Tombstone = $targetState + $suffix })
if ($null -ne $guidancePlan) { $pairs += @([pscustomobject]@{ Original = $guidancePlan.BlockPath; Tombstone = $guidancePlan.BlockPath + $suffix }); if ($guidancePlan.Action -eq "appended") { $pairs += [pscustomobject]@{ Original = $guidancePlan.BackupPath; Tombstone = $guidancePlan.BackupPath + $suffix } } }
$moved = [System.Collections.Generic.List[object]]::new()
$guidanceMutated = $false; $guidanceOriginalBytes = $null; $guidanceMutationPostHash = $null; $guidanceLeftEmpty = $false
if ($null -ne $guidancePlan) { Invoke-TestPause "uninstall-before-guidance-mutation" }
try {
    foreach ($pair in $pairs) { [IO.File]::Move($pair.Original, $pair.Tombstone); [void]$moved.Add($pair) }
    if ($null -ne $guidancePlan) {
        Assert-PlainFile $guidancePlan.Path
        $guidanceStream = [IO.File]::Open($guidancePlan.Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            Assert-PlainFile $guidancePlan.Path
            $freshBytes = Read-StreamBytes $guidanceStream; Assert-GuidanceText $freshBytes $guidancePlan.Path
            $freshText = [Text.UTF8Encoding]::new($false, $true).GetString($freshBytes)
            $beginMarker = "<!-- SOL-ULTRA-WORKAROUND:BEGIN -->"; $endMarker = "<!-- SOL-ULTRA-WORKAROUND:END -->"
            $freshMarkerCount = ([regex]::Matches($freshText, [regex]::Escape($beginMarker))).Count + ([regex]::Matches($freshText, [regex]::Escape($endMarker))).Count
            $freshOccurrences = Find-ByteOccurrences $freshBytes $guidancePlan.BlockBytes
            if ($freshOccurrences.Count -ne 1 -or $freshMarkerCount -ne 2) { throw "Managed guidance block changed after validation. Refusing to remove anything." }
            if ((Get-Sha256Bytes $freshBytes) -eq $state.guidance_post_sha256) {
                if ($guidancePlan.Action -eq "appended") {
                    $backupTombstone = $guidancePlan.BackupPath + $suffix
                    Assert-PlainFile $backupTombstone
                    $replacementBytes = [IO.File]::ReadAllBytes($backupTombstone)
                    if ((Get-Sha256Bytes $replacementBytes) -ne $state.guidance_backup_sha256) { throw "Guidance backup changed during uninstall. Refusing to remove anything." }
                } else {
                    $replacementBytes = [byte[]]@(); $guidanceLeftEmpty = $true
                }
            } else {
                $replacementBytes = Remove-ByteRange $freshBytes $freshOccurrences[0] $guidancePlan.BlockBytes.Length
            }
            $guidanceOriginalBytes = $freshBytes; $guidanceMutationPostHash = Get-Sha256Bytes $replacementBytes; $guidanceMutated = $true
            Write-StreamBytes $guidanceStream $replacementBytes
        } finally { $guidanceStream.Dispose() }
    }
} catch {
    $originalError = $_; $unsafeGuidanceRollback = $false; $rollbackError = $null
    if ($guidanceMutated -and $null -ne $guidancePlan) {
        $rollbackStream = $null
        try {
            Assert-PlainFile $guidancePlan.Path
            $rollbackStream = [IO.File]::Open($guidancePlan.Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            Assert-PlainFile $guidancePlan.Path
            $currentBytes = Read-StreamBytes $rollbackStream
            if ((Get-Sha256Bytes $currentBytes) -ne $guidanceMutationPostHash) {
                $unsafeGuidanceRollback = $true; $rollbackError = "Guidance changed after the uninstaller wrote it."
            } else { Write-StreamBytes $rollbackStream $guidanceOriginalBytes }
        } catch {
            $unsafeGuidanceRollback = $true; $rollbackError = $_.Exception.Message
        } finally { if ($null -ne $rollbackStream) { $rollbackStream.Dispose() } }
    }
    if ($unsafeGuidanceRollback) {
        throw "Uninstall failed, and guidance rollback was unsafe: $rollbackError The current guidance and staged recovery files were preserved. Original error: $($originalError.Exception.Message)"
    }
    for ($i = $moved.Count - 1; $i -ge 0; $i--) { if ((Test-Path -LiteralPath $moved[$i].Tombstone) -and -not (Test-Path -LiteralPath $moved[$i].Original)) { [IO.File]::Move($moved[$i].Tombstone, $moved[$i].Original) } }
    throw "Uninstall could not stage all files; the installation was restored. $($originalError.Exception.Message)"
}

$cleanupFailures = [System.Collections.Generic.List[string]]::new()
foreach ($pair in $moved) { try { Remove-Item -Force -LiteralPath $pair.Tombstone } catch { [void]$cleanupFailures.Add($pair.Tombstone) } }
if ($cleanupFailures.Count -gt 0) { throw "The workaround is disabled, but cleanup failed for: $($cleanupFailures -join ', ')" }
Remove-EmptyRecordedDirectory $agentParent $state.agent_parent_created; Remove-EmptyRecordedDirectory $configParent $state.config_parent_created
Write-Host "Uninstalled SOL Ultra Workaround from $Mode mode."
Write-Host "No pre-existing Codex file was changed or removed."
if ($guidanceLeftEmpty) { Write-Host "The installer-created guidance file was left empty to avoid a delete race." }
