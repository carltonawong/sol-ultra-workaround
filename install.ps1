[CmdletBinding()]
param(
    [ValidateSet("profile", "project")]
    [string]$Mode,
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"

function Assert-PlainDirectoryIfPresent([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    if (-not $item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing a non-directory, linked, or redirected target: $Path"
    }
}

function Assert-PlainFileIfPresent([string]$Path) {
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Refusing a non-file, linked, or redirected target: $Path"
    }
    return $item
}

function Assert-NoReparseAncestors([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -Force -LiteralPath $cursor -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0))) {
            throw "Refusing a path with a linked or redirected ancestor: $cursor"
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Copy-NewFile([string]$Source, [string]$Target, [System.Collections.Generic.List[string]]$CreatedFiles) {
    $inputStream = $null; $outputStream = $null
    try {
        $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $outputStream = [IO.File]::Open($Target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        [void]$CreatedFiles.Add($Target)
        $inputStream.CopyTo($outputStream); $outputStream.Flush()
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
    }
}

function Write-NewUtf8File([string]$Target, [string]$Text, [System.Collections.Generic.List[string]]$CreatedFiles) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream = $null
    try {
        $stream = [IO.File]::Open($Target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        [void]$CreatedFiles.Add($Target)
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Remove-EmptyCreatedDirectory([string]$Path, [bool]$WasCreated) {
    if ($WasCreated -and (Test-Path -LiteralPath $Path -PathType Container) -and -not (Get-ChildItem -Force -LiteralPath $Path | Select-Object -First 1)) {
        Remove-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
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

function Join-ByteArrays([byte[][]]$Arrays) {
    $length = 0
    foreach ($array in $Arrays) { $length += $array.Length }
    $result = [byte[]]::new($length); $offset = 0
    foreach ($array in $Arrays) {
        if ($array.Length -gt 0) { [Array]::Copy($array, 0, $result, $offset, $array.Length); $offset += $array.Length }
    }
    return $result
}

function Write-NewBytesFile([string]$Target, [byte[]]$Bytes, [System.Collections.Generic.List[string]]$CreatedFiles) {
    $stream = $null
    try {
        $stream = [IO.File]::Open($Target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        [void]$CreatedFiles.Add($Target)
        if ($Bytes.Length -gt 0) { $stream.Write($Bytes, 0, $Bytes.Length) }
        $stream.Flush()
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
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

function Assert-GuidanceText([byte[]]$Bytes, [string]$Path) {
    if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe) -or ($Bytes[0] -eq 0xfe -and $Bytes[1] -eq 0xff))) {
        throw "Refusing UTF-16 guidance file: $Path"
    }
    if ($Bytes.Length -ge 4 -and (($Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x00) -or ($Bytes[0] -eq 0x00 -and $Bytes[1] -eq 0x00 -and $Bytes[2] -eq 0xfe -and $Bytes[3] -eq 0xff))) {
        throw "Refusing UTF-32 guidance file: $Path"
    }
    if ($Bytes -contains 0) { throw "Refusing clearly non-text guidance file: $Path" }
    try { [void]([Text.UTF8Encoding]::new($false, $true).GetString($Bytes)) }
    catch { throw "Refusing non-UTF-8 guidance file: $Path" }
}

function Get-GuidanceMarkers([string]$BlockText) {
    $start = "<!-- SOL-ULTRA-WORKAROUND:BEGIN -->"
    $end = "<!-- SOL-ULTRA-WORKAROUND:END -->"
    if (([regex]::Matches($BlockText, [regex]::Escape($start))).Count -ne 1 -or
        ([regex]::Matches($BlockText, [regex]::Escape($end))).Count -ne 1) {
        throw "The packaged guidance block must contain one exact begin marker and one exact end marker."
    }
    return [pscustomobject]@{ Start = $start; End = $end }
}

if ([string]::IsNullOrWhiteSpace($Mode)) { throw "Mode is required. CLI: ./install.ps1 -Mode profile. Desktop/IDE: ./install.ps1 -Mode project -ProjectRoot <absolute-project-root>." }
if ($Mode -eq "project" -and [string]::IsNullOrWhiteSpace($ProjectRoot)) { throw "ProjectRoot is required in project mode and must be an absolute path." }
if ($Mode -eq "profile" -and -not [string]::IsNullOrWhiteSpace($ProjectRoot)) { throw "ProjectRoot is valid only in project mode." }

$packageRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$sourceConfig = Join-Path $packageRoot "profiles\sol-ultra.config.toml"
$sourceAgent = Join-Path $packageRoot "agents\terra-high.toml"
$sourceGuidance = Join-Path $packageRoot "profiles\sol-ultra.AGENTS.md"
foreach ($source in @($sourceConfig, $sourceAgent)) { if ($null -eq (Assert-PlainFileIfPresent $source)) { throw "Required package file is missing: $source" } }
$codexHome = if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME) } else { [IO.Path]::GetFullPath((Join-Path $HOME ".codex")) }
Assert-NoReparseAncestors $codexHome
if (Test-Path -LiteralPath $codexHome -PathType Container) { $codexHome = (Resolve-Path -LiteralPath $codexHome).Path }
$legacyDefault = Join-Path $codexHome "agents\default.toml"
if ($null -ne (Get-Item -Force -LiteralPath $legacyDefault -ErrorAction SilentlyContinue)) { throw "Existing global agents/default.toml detected. Remove or review the legacy/global override before installing this scoped version." }

$guidanceAction = "none"; $guidanceFile = "none"; $guidancePreHash = "none"; $guidancePostHash = "none"; $guidanceBackupHash = "none"; $guidanceBlockHash = "none"
if ($Mode -eq "profile") {
    $targetConfig = Join-Path $codexHome "sol-ultra.config.toml"
    $targetAgent = Join-Path $codexHome "sol-ultra-workaround\terra-high.toml"
} else {
    if (-not [IO.Path]::IsPathRooted($ProjectRoot)) { throw "ProjectRoot must be an absolute path: $ProjectRoot" }
    $projectCandidate = [IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $projectCandidate -PathType Container)) { throw "Project root does not exist: $projectCandidate" }
    Assert-NoReparseAncestors $projectCandidate
    $resolvedProject = (Resolve-Path -LiteralPath $projectCandidate).Path
    $resolvedHome = (Resolve-Path -LiteralPath $HOME).Path; $trimChars = [char[]]"\\/"; $resolvedRoot = [IO.Path]::GetPathRoot($resolvedProject)
    if ($resolvedProject.TrimEnd($trimChars) -ieq $resolvedRoot.TrimEnd($trimChars)) { throw "Refusing to turn a filesystem root into project mode." }
    if ($resolvedProject -ieq $codexHome -or $resolvedProject -ieq $resolvedHome) { throw "Refusing unsafe project root." }
    $packagePrefix = $packageRoot.TrimEnd($trimChars) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedProject -ieq $packageRoot -or $resolvedProject.StartsWith($packagePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to install project mode into the package checkout." }
    $projectCodexDir = Join-Path $resolvedProject ".codex"; Assert-PlainDirectoryIfPresent $projectCodexDir
    $targetConfig = [IO.Path]::GetFullPath((Join-Path $projectCodexDir "config.toml")); $baseConfig = [IO.Path]::GetFullPath((Join-Path $codexHome "config.toml"))
    if ($targetConfig -ieq $baseConfig) { throw "Refusing to turn the user's base Codex config into project mode." }
    $existingProjectDefault = Join-Path $projectCodexDir "agents\default.toml"
    if ($null -ne (Get-Item -Force -LiteralPath $existingProjectDefault -ErrorAction SilentlyContinue)) { throw "Refusing to shadow existing project agent: $existingProjectDefault" }
    $targetAgent = Join-Path $projectCodexDir "sol-ultra-workaround\terra-high.toml"
    if ($null -eq (Assert-PlainFileIfPresent $sourceGuidance)) { throw "Required package guidance block is missing: $sourceGuidance" }
    $blockBytes = [IO.File]::ReadAllBytes($sourceGuidance); Assert-GuidanceText $blockBytes $sourceGuidance
    if ($blockBytes.Length -ge 3 -and $blockBytes[0] -eq 0xef -and $blockBytes[1] -eq 0xbb -and $blockBytes[2] -eq 0xbf) { throw "Packaged guidance block must be UTF-8 without BOM." }
    $blockText = [Text.UTF8Encoding]::new($false, $true).GetString($blockBytes); $markers = Get-GuidanceMarkers $blockText
    $override = Join-Path $resolvedProject "AGENTS.override.md"; $agents = Join-Path $resolvedProject "AGENTS.md"
    if ($null -ne (Assert-PlainFileIfPresent $override)) { $guidancePath = $override; $guidanceFile = "AGENTS.override.md" } else { $guidancePath = $agents; $guidanceFile = "AGENTS.md" }
    $guidanceItem = Assert-PlainFileIfPresent $guidancePath
    if ($null -ne $guidanceItem) {
        $guidanceBytes = [IO.File]::ReadAllBytes($guidancePath); Assert-GuidanceText $guidanceBytes $guidancePath
        $guidanceText = [Text.UTF8Encoding]::new($false, $true).GetString($guidanceBytes)
        if ($guidanceText.IndexOf($markers.Start, [StringComparison]::Ordinal) -ge 0 -or $guidanceText.IndexOf($markers.End, [StringComparison]::Ordinal) -ge 0) { throw "Existing managed guidance markers detected. Refusing to modify: $guidancePath" }
        $guidanceAction = "appended"; $guidancePreHash = Get-Sha256 $guidancePath
    } else { $guidanceBytes = [byte[]]@(); $guidanceAction = "created" }
}

$configParent = Split-Path -Parent $targetConfig; $agentParent = Split-Path -Parent $targetAgent
Assert-PlainDirectoryIfPresent $configParent; Assert-PlainDirectoryIfPresent $agentParent
$targetState = Join-Path $agentParent "install-state.txt"; $targetBlock = Join-Path $agentParent "guidance-block.md"; $targetBackup = Join-Path $agentParent ($guidanceFile + ".preinstall.bak")
$ownedTargets = @($targetConfig, $targetAgent, $targetState)
if ($Mode -eq "project") { $ownedTargets += @($targetBlock, $targetBackup) }
foreach ($target in $ownedTargets) { if ($null -ne (Get-Item -Force -LiteralPath $target -ErrorAction SilentlyContinue)) { throw "Refusing to overwrite existing filesystem object: $target" } }

$configParentCreated = -not (Test-Path -LiteralPath $configParent -PathType Container); $agentParentCreated = -not (Test-Path -LiteralPath $agentParent -PathType Container)
$created = [System.Collections.Generic.List[string]]::new(); $guidanceCreatedFiles = [System.Collections.Generic.List[string]]::new()
$guidanceChanged = $false; $guidanceLeftEmpty = $false
try {
    New-Item -ItemType Directory -Force -Path $configParent | Out-Null; New-Item -ItemType Directory -Force -Path $agentParent | Out-Null
    Copy-NewFile $sourceConfig $targetConfig $created; Copy-NewFile $sourceAgent $targetAgent $created
    if ($Mode -eq "project") {
        Copy-NewFile $sourceGuidance $targetBlock $created; $guidanceBlockHash = Get-Sha256 $targetBlock
        if ($guidanceFile -eq "AGENTS.md" -and $null -ne (Assert-PlainFileIfPresent $override)) { throw "AGENTS.override.md appeared during installation. Refusing to modify inactive guidance." }
        if ($guidanceAction -eq "created") {
            $guidancePostHash = Get-Sha256Bytes $blockBytes
            Copy-NewFile $sourceGuidance $guidancePath $guidanceCreatedFiles
            $guidanceChanged = $true
        } else {
            Assert-PlainFileIfPresent $guidancePath | Out-Null
            $stream = [IO.File]::Open($guidancePath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            try {
                Assert-PlainFileIfPresent $guidancePath | Out-Null
                $guidanceBytes = Read-StreamBytes $stream; Assert-GuidanceText $guidanceBytes $guidancePath
                $guidanceText = [Text.UTF8Encoding]::new($false, $true).GetString($guidanceBytes)
                if ($guidanceText.IndexOf($markers.Start, [StringComparison]::Ordinal) -ge 0 -or $guidanceText.IndexOf($markers.End, [StringComparison]::Ordinal) -ge 0) { throw "Existing managed guidance markers detected. Refusing to modify: $guidancePath" }
                $guidancePreHash = Get-Sha256Bytes $guidanceBytes
                Write-NewBytesFile $targetBackup $guidanceBytes $created; $guidanceBackupHash = $guidancePreHash
                $separator = if ($guidanceBytes.Length -eq 0 -or $guidanceBytes[$guidanceBytes.Length - 1] -eq 10 -or $guidanceBytes[$guidanceBytes.Length - 1] -eq 13) { [byte[]]@() } else { [byte[]]@(13, 10) }
                $postBytes = Join-ByteArrays @($guidanceBytes, $separator, $blockBytes)
                $guidancePostHash = Get-Sha256Bytes $postBytes; $guidanceChanged = $true
                Write-StreamBytes $stream $postBytes
            } finally { $stream.Dispose() }
        }
        Invoke-TestPause "install-after-guidance"
    }
    $configHash = Get-Sha256 $targetConfig; $agentHash = Get-Sha256 $targetAgent
    if ($configHash -ne (Get-Sha256 $sourceConfig) -or $agentHash -ne (Get-Sha256 $sourceAgent)) { throw "Installed payload verification failed." }
    $configDirFlag = if ($configParentCreated) { "1" } else { "0" }; $agentDirFlag = if ($agentParentCreated) { "1" } else { "0" }
    $stateText = "schema=2`nmode=$Mode`nconfig_sha256=$configHash`nagent_sha256=$agentHash`nconfig_parent_created=$configDirFlag`nagent_parent_created=$agentDirFlag`nguidance_action=$guidanceAction`nguidance_file=$guidanceFile`nguidance_pre_sha256=$guidancePreHash`nguidance_post_sha256=$guidancePostHash`nguidance_backup_sha256=$guidanceBackupHash`nguidance_block_sha256=$guidanceBlockHash`n"
    Write-NewUtf8File $targetState $stateText $created
} catch {
    $originalError = $_; $unsafeGuidanceRollback = $false; $rollbackError = $null
    if ($guidanceAction -eq "created" -and $guidanceCreatedFiles.Count -gt 0) { $guidanceChanged = $true }
    if ($guidanceChanged) {
        $rollbackStream = $null
        try {
            Assert-PlainFileIfPresent $guidancePath | Out-Null
            $rollbackStream = [IO.File]::Open($guidancePath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            Assert-PlainFileIfPresent $guidancePath | Out-Null
            $currentBytes = Read-StreamBytes $rollbackStream
            if ((Get-Sha256Bytes $currentBytes) -ne $guidancePostHash) {
                $unsafeGuidanceRollback = $true
                $rollbackError = "Guidance changed after the installer wrote it."
            } elseif ($guidanceAction -eq "appended") {
                Assert-PlainFileIfPresent $targetBackup | Out-Null
                $backupBytes = [IO.File]::ReadAllBytes($targetBackup)
                if ((Get-Sha256Bytes $backupBytes) -ne $guidanceBackupHash) { throw "Guidance backup changed before rollback." }
                Write-StreamBytes $rollbackStream $backupBytes
            } else {
                Write-StreamBytes $rollbackStream ([byte[]]@())
                $guidanceLeftEmpty = $true
            }
        } catch {
            $unsafeGuidanceRollback = $true
            $rollbackError = $_.Exception.Message
        } finally { if ($null -ne $rollbackStream) { $rollbackStream.Dispose() } }
    }
    if ($unsafeGuidanceRollback) {
        throw "Installation failed, and guidance rollback was unsafe: $rollbackError The guidance and recovery files were preserved for manual recovery. Original error: $($originalError.Exception.Message)"
    }
    for ($i = $created.Count - 1; $i -ge 0; $i--) { Remove-Item -Force -LiteralPath $created[$i] -ErrorAction SilentlyContinue }
    Remove-EmptyCreatedDirectory $agentParent $agentParentCreated; Remove-EmptyCreatedDirectory $configParent $configParentCreated
    if ($guidanceLeftEmpty) { throw "Installation failed and was rolled back; the installer-created guidance file was left empty to avoid a delete race. Original error: $($originalError.Exception.Message)" }
    throw $originalError
}

Write-Host "Installed SOL Ultra Workaround in $Mode mode."
if ($Mode -eq "profile") {
    Write-Host "No existing Codex file was overwritten."
    Write-Host "Launch: codex --profile sol-ultra"
    Write-Host "Resume: codex resume --profile sol-ultra <SESSION_ID_OR_NAME>"
} else {
    Write-Host "Managed guidance ($guidanceAction): $guidancePath"
    if ($guidanceAction -eq "appended") { Write-Host "Pre-install guidance backup: $targetBackup" }
    Write-Host "Project Codex payloads were newly created; the active guidance file was managed as reported above."
    Write-Host "Project mode: open and trust this folder or workspace, then create a new task inside it: $resolvedProject"
}
