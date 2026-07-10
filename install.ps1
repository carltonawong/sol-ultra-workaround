[CmdletBinding()]
param(
    [ValidateSet("profile", "project")]
    [string]$Mode,
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Mode)) {
    throw "Mode is required. CLI: ./install.ps1 -Mode profile. Desktop/IDE: ./install.ps1 -Mode project -ProjectRoot <absolute-project-root>."
}
if ($Mode -eq "project" -and [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw "ProjectRoot is required in project mode and must be an absolute path."
}
if ($Mode -eq "profile" -and -not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw "ProjectRoot is valid only in project mode."
}

function Assert-PlainDirectoryIfPresent([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }
    if (-not $item.PSIsContainer) {
        throw "Expected a directory but found another filesystem object: $Path"
    }
    if ($item.LinkType -or
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing a linked or redirected target directory: $Path"
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

function Copy-NewFile(
    [string]$Source,
    [string]$Target,
    [System.Collections.Generic.List[string]]$CreatedFiles
) {
    $inputStream = $null
    $outputStream = $null
    try {
        $inputStream = [IO.File]::Open(
            $Source,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        $outputStream = [IO.File]::Open(
            $Target,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        [void]$CreatedFiles.Add($Target)
        $inputStream.CopyTo($outputStream)
        $outputStream.Flush()
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
    }
}

function Write-NewUtf8File(
    [string]$Target,
    [string]$Text,
    [System.Collections.Generic.List[string]]$CreatedFiles
) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = $null
    try {
        $stream = [IO.File]::Open(
            $Target,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        [void]$CreatedFiles.Add($Target)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Remove-EmptyCreatedDirectory([string]$Path, [bool]$WasCreated) {
    if ($WasCreated -and (Test-Path -LiteralPath $Path -PathType Container) -and
        -not (Get-ChildItem -Force -LiteralPath $Path | Select-Object -First 1)) {
        Remove-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    }
}

$packageRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$sourceConfig = Join-Path $packageRoot "profiles\sol-ultra.config.toml"
$sourceAgent = Join-Path $packageRoot "agents\terra-high.toml"
$codexHome = if ($env:CODEX_HOME) {
    [IO.Path]::GetFullPath($env:CODEX_HOME)
} else {
    [IO.Path]::GetFullPath((Join-Path $HOME ".codex"))
}
Assert-NoReparseAncestors $codexHome
if (Test-Path -LiteralPath $codexHome -PathType Container) {
    $codexHome = (Resolve-Path -LiteralPath $codexHome).Path
}

$legacyDefault = Join-Path $codexHome "agents\default.toml"
if ($null -ne (Get-Item -Force -LiteralPath $legacyDefault -ErrorAction SilentlyContinue)) {
    throw "Existing global agents/default.toml detected. Remove or review the legacy/global override before installing this scoped version."
}

if ($Mode -eq "profile") {
    $targetConfig = Join-Path $codexHome "sol-ultra.config.toml"
    $targetAgent = Join-Path $codexHome "sol-ultra-workaround\terra-high.toml"
} else {
    if (-not [IO.Path]::IsPathRooted($ProjectRoot)) {
        throw "ProjectRoot must be an absolute path: $ProjectRoot"
    }
    $projectCandidate = [IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $projectCandidate -PathType Container)) {
        throw "Project root does not exist: $projectCandidate"
    }
    Assert-NoReparseAncestors $projectCandidate
    $resolvedProject = (Resolve-Path -LiteralPath $projectCandidate).Path
    $resolvedHome = (Resolve-Path -LiteralPath $HOME).Path
    $trimChars = [char[]]"\/"
    $resolvedRoot = [IO.Path]::GetPathRoot($resolvedProject)
    if ($resolvedProject.TrimEnd($trimChars) -ieq $resolvedRoot.TrimEnd($trimChars)) {
        throw "Refusing to turn a filesystem root into project mode."
    }
    if ($resolvedProject -ieq $codexHome) {
        throw "Refusing to turn CODEX_HOME into project mode."
    }
    $packagePrefix = $packageRoot.TrimEnd($trimChars) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedProject -ieq $packageRoot -or
        $resolvedProject.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to install project mode into the package checkout."
    }
    if ($resolvedProject -ieq $resolvedHome) {
        throw "Refusing to turn the user's home directory into project mode."
    }

    $projectCodexDir = Join-Path $resolvedProject ".codex"
    Assert-PlainDirectoryIfPresent $projectCodexDir
    $candidateConfig = [IO.Path]::GetFullPath(
        (Join-Path $projectCodexDir "config.toml")
    )
    $baseConfig = [IO.Path]::GetFullPath((Join-Path $codexHome "config.toml"))
    if ($candidateConfig -ieq $baseConfig) {
        throw "Refusing to turn the user's base Codex config into project mode."
    }

    $existingProjectDefault = Join-Path $projectCodexDir "agents\default.toml"
    if ($null -ne (Get-Item -Force -LiteralPath $existingProjectDefault -ErrorAction SilentlyContinue)) {
        throw "Refusing to shadow existing project agent: $existingProjectDefault"
    }
    $targetConfig = $candidateConfig
    $targetAgent = Join-Path $projectCodexDir "sol-ultra-workaround\terra-high.toml"
}

$configParent = Split-Path -Parent $targetConfig
$agentParent = Split-Path -Parent $targetAgent
Assert-PlainDirectoryIfPresent $configParent
Assert-PlainDirectoryIfPresent $agentParent
$targetState = Join-Path $agentParent "install-state.txt"

foreach ($target in @($targetConfig, $targetAgent, $targetState)) {
    if ($null -ne (Get-Item -Force -LiteralPath $target -ErrorAction SilentlyContinue)) {
        throw "Refusing to overwrite existing filesystem object: $target"
    }
}

$configParentCreated = -not (Test-Path -LiteralPath $configParent -PathType Container)
$agentParentCreated = -not (Test-Path -LiteralPath $agentParent -PathType Container)
$created = [System.Collections.Generic.List[string]]::new()
try {
    New-Item -ItemType Directory -Force -Path $configParent | Out-Null
    New-Item -ItemType Directory -Force -Path $agentParent | Out-Null

    Copy-NewFile $sourceConfig $targetConfig $created
    Copy-NewFile $sourceAgent $targetAgent $created

    $configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetConfig).Hash.ToLowerInvariant()
    $agentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetAgent).Hash.ToLowerInvariant()
    if ($configHash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceConfig).Hash.ToLowerInvariant()) {
        throw "Profile/config verification failed."
    }
    if ($agentHash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceAgent).Hash.ToLowerInvariant()) {
        throw "Agent verification failed."
    }

    $configDirFlag = if ($configParentCreated) { "1" } else { "0" }
    $agentDirFlag = if ($agentParentCreated) { "1" } else { "0" }
    $stateText = "schema=1`nmode=$Mode`nconfig_sha256=$configHash`nagent_sha256=$agentHash`nconfig_parent_created=$configDirFlag`nagent_parent_created=$agentDirFlag`n"
    Write-NewUtf8File $targetState $stateText $created
} catch {
    for ($i = $created.Count - 1; $i -ge 0; $i--) {
        Remove-Item -Force -LiteralPath $created[$i] -ErrorAction SilentlyContinue
    }
    Remove-EmptyCreatedDirectory $agentParent $agentParentCreated
    Remove-EmptyCreatedDirectory $configParent $configParentCreated
    throw
}

Write-Host "Installed SOL Ultra Workaround in $Mode mode."
Write-Host "No existing Codex file was overwritten."
if ($Mode -eq "profile") {
    Write-Host "Launch: codex --profile sol-ultra"
    Write-Host "Resume: codex resume --profile sol-ultra <SESSION_ID_OR_NAME>"
} else {
    Write-Host "Fully quit and restart Codex, then open the project: $resolvedProject"
}
