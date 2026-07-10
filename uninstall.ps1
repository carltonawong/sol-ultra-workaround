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
    if (-not $item.PSIsContainer -or $item.LinkType -or
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing a non-directory, linked, or redirected target: $Path"
    }
}

function Assert-NoReparseAncestors([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -Force -LiteralPath $cursor -ErrorAction SilentlyContinue
        if ($null -ne $item -and
            ($item.LinkType -or
             (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0))) {
            throw "Refusing a path with a linked or redirected ancestor: $cursor"
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Remove-EmptyRecordedDirectory([string]$Path, [string]$CreatedFlag) {
    if ($CreatedFlag -eq "1" -and (Test-Path -LiteralPath $Path -PathType Container) -and
        -not (Get-ChildItem -Force -LiteralPath $Path | Select-Object -First 1)) {
        Remove-Item -Force -LiteralPath $Path
    }
}

$packageRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$codexHome = if ($env:CODEX_HOME) {
    [IO.Path]::GetFullPath($env:CODEX_HOME)
} else {
    [IO.Path]::GetFullPath((Join-Path $HOME ".codex"))
}
Assert-NoReparseAncestors $codexHome
if (Test-Path -LiteralPath $codexHome -PathType Container) {
    $codexHome = (Resolve-Path -LiteralPath $codexHome).Path
}

if ($Mode -eq "profile") {
    $targetConfig = Join-Path $codexHome "sol-ultra.config.toml"
    $targetAgent = Join-Path $codexHome "sol-ultra-workaround\terra-high.toml"
} else {
    $projectCandidate = [IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $projectCandidate -PathType Container)) {
        throw "Project root does not exist: $projectCandidate"
    }
    Assert-NoReparseAncestors $projectCandidate
    $resolvedProject = (Resolve-Path -LiteralPath $projectCandidate).Path
    $resolvedHome = (Resolve-Path -LiteralPath $HOME).Path
    if ($resolvedProject -ieq $resolvedHome) {
        throw "Refusing to treat the user's home directory as project mode."
    }
    if ($resolvedProject -ieq $packageRoot -and
        (Test-Path -LiteralPath (Join-Path $packageRoot "profiles\sol-ultra.config.toml"))) {
        throw "Refusing to treat the package checkout as project mode."
    }
    $projectCodexDir = Join-Path $resolvedProject ".codex"
    Assert-PlainDirectoryIfPresent $projectCodexDir
    $targetConfig = [IO.Path]::GetFullPath((Join-Path $projectCodexDir "config.toml"))
    $baseConfig = [IO.Path]::GetFullPath((Join-Path $codexHome "config.toml"))
    if ($targetConfig -ieq $baseConfig) {
        throw "Refusing to treat the user's base Codex config as project mode."
    }
    $targetAgent = Join-Path $projectCodexDir "sol-ultra-workaround\terra-high.toml"
}

$configParent = Split-Path -Parent $targetConfig
$agentParent = Split-Path -Parent $targetAgent
Assert-PlainDirectoryIfPresent $configParent
Assert-PlainDirectoryIfPresent $agentParent
$targetState = Join-Path $agentParent "install-state.txt"

$present = @($targetConfig, $targetAgent, $targetState) |
    Where-Object { $null -ne (Get-Item -Force -LiteralPath $_ -ErrorAction SilentlyContinue) }
if ($present.Count -eq 0) {
    Write-Host "SOL Ultra Workaround is not installed in $Mode mode."
    return
}
if ($present.Count -ne 3) {
    throw "Partial installation detected. Refusing to remove anything."
}

$allowedKeys = @(
    "schema", "mode", "config_sha256", "agent_sha256",
    "config_parent_created", "agent_parent_created"
)
$state = @{}
foreach ($line in Get-Content -LiteralPath $targetState) {
    $parts = $line -split "=", 2
    if ($parts.Count -ne 2 -or $parts[0] -notin $allowedKeys -or
        $state.ContainsKey($parts[0])) {
        throw "Invalid install state. Refusing to remove anything."
    }
    $state[$parts[0]] = $parts[1]
}
if ($state.Count -ne 6 -or $state.schema -ne "1" -or $state.mode -ne $Mode -or
    $state.config_sha256 -notmatch "^[0-9a-f]{64}$" -or
    $state.agent_sha256 -notmatch "^[0-9a-f]{64}$" -or
    $state.config_parent_created -notin @("0", "1") -or
    $state.agent_parent_created -notin @("0", "1")) {
    throw "Invalid install state. Refusing to remove anything."
}
if ($state.config_sha256 -ne
    (Get-FileHash -Algorithm SHA256 -LiteralPath $targetConfig).Hash.ToLowerInvariant()) {
    throw "Installed config hash does not match. Refusing to delete it."
}
if ($state.agent_sha256 -ne
    (Get-FileHash -Algorithm SHA256 -LiteralPath $targetAgent).Hash.ToLowerInvariant()) {
    throw "Installed agent hash does not match. Refusing to delete it."
}

$suffix = ".sol-ultra-remove-" + [Guid]::NewGuid().ToString("N")
$pairs = @(
    [pscustomobject]@{ Original = $targetConfig; Tombstone = $targetConfig + $suffix },
    [pscustomobject]@{ Original = $targetAgent; Tombstone = $targetAgent + $suffix },
    [pscustomobject]@{ Original = $targetState; Tombstone = $targetState + $suffix }
)
$moved = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($pair in $pairs) {
        [IO.File]::Move($pair.Original, $pair.Tombstone)
        [void]$moved.Add($pair)
    }
} catch {
    for ($i = $moved.Count - 1; $i -ge 0; $i--) {
        if ((Test-Path -LiteralPath $moved[$i].Tombstone) -and
            -not (Test-Path -LiteralPath $moved[$i].Original)) {
            [IO.File]::Move($moved[$i].Tombstone, $moved[$i].Original)
        }
    }
    throw "Uninstall could not stage all files; the installation was restored. $($_.Exception.Message)"
}

$cleanupFailures = [System.Collections.Generic.List[string]]::new()
foreach ($pair in $moved) {
    try {
        Remove-Item -Force -LiteralPath $pair.Tombstone
    } catch {
        [void]$cleanupFailures.Add($pair.Tombstone)
    }
}
if ($cleanupFailures.Count -gt 0) {
    throw "The workaround is disabled, but cleanup failed for: $($cleanupFailures -join ', ')"
}

Remove-EmptyRecordedDirectory $agentParent $state.agent_parent_created
Remove-EmptyRecordedDirectory $configParent $state.config_parent_created
Write-Host "Uninstalled SOL Ultra Workaround from $Mode mode."
Write-Host "No pre-existing Codex file was changed or removed."
