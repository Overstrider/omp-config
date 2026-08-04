[CmdletBinding()]
param(
    [string]$SourceDirectory,
    [switch]$ForceRebuild,
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $repoRoot 'fork/manifest.json'
$runtimeStatePath = Join-Path $repoRoot 'run/omp-fork-runtime.json'

function Resolve-ApplicationPath {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        throw "Required executable is unavailable on PATH: $Name"
    }
    if ($command.Path) {
        return $command.Path
    }
    return $command.Source
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

function Test-GitPatch {
    param(
        [Parameter(Mandatory)][string]$GitExecutable,
        [Parameter(Mandatory)][string]$Checkout,
        [Parameter(Mandatory)][string]$Patch,
        [switch]$Reverse
    )

    $arguments = @('-C', $Checkout, 'apply')
    if ($Reverse) {
        $arguments += '--reverse'
    }
    $arguments += @('--check', $Patch)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $GitExecutable @arguments 2>$null | Out-Null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return $exitCode -eq 0
}

function Install-PublishedNativeAddon {
    param(
        [Parameter(Mandatory)][string]$BunExecutable,
        [Parameter(Mandatory)][string]$Checkout,
        [Parameter(Mandatory)][string]$RuntimeRoot
    )

    $runningOnWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
    if ($runningOnWindows) {
        $platform = 'win32'
        $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
            'arm64'
        } else {
            'x64'
        }
    } else {
        $unameExecutable = Resolve-ApplicationPath 'uname'
        $unameSystem = (& $unameExecutable -s 2>&1 | Out-String).Trim()
        $unameMachine = (& $unameExecutable -m 2>&1 | Out-String).Trim()
        $platform = if ($unameSystem -eq 'Darwin') { 'darwin' } else { 'linux' }
        $architecture = if ($unameMachine -in @('arm64', 'aarch64')) { 'arm64' } else { 'x64' }
    }

    $nativeDirectory = Join-Path $Checkout 'packages/natives/native'
    $existingAddons = @(Get-ChildItem -LiteralPath $nativeDirectory -Filter (
        "pi_natives.$platform-$architecture*.node"
    ) -File -ErrorAction SilentlyContinue)
    if ($existingAddons.Count -gt 0) {
        return
    }

    $nativeManifestPath = Join-Path $Checkout 'packages/natives/package.json'
    $nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw | ConvertFrom-Json
    $nativePackageName = "@oh-my-pi/pi-natives-$platform-$architecture"
    $nativePackageSpec = "$nativePackageName@$($nativeManifest.version)"
    $nativeCacheDirectory = Join-Path $RuntimeRoot (
        "native-$platform-$architecture-$($nativeManifest.version)"
    )
    New-Item -ItemType Directory -Path $nativeCacheDirectory -Force | Out-Null
    $cacheManifestPath = Join-Path $nativeCacheDirectory 'package.json'
    if (-not (Test-Path -LiteralPath $cacheManifestPath -PathType Leaf)) {
        [IO.File]::WriteAllText(
            $cacheManifestPath,
            "{`n  `"private`": true`n}`n",
            [Text.UTF8Encoding]::new($false)
        )
    }
    Invoke-CheckedCommand $BunExecutable @(
        'add', '--exact', '--cwd', $nativeCacheDirectory, $nativePackageSpec
    ) $RuntimeRoot

    $installedPackageDirectory = Join-Path (
        $nativeCacheDirectory
    ) "node_modules/$nativePackageName"
    $publishedAddons = @(Get-ChildItem -LiteralPath $installedPackageDirectory -Filter (
        'pi_natives*.node'
    ) -File)
    if ($publishedAddons.Count -eq 0) {
        throw "Published native package contains no addon: $nativePackageSpec"
    }
    foreach ($addon in $publishedAddons) {
        Copy-Item -LiteralPath $addon.FullName -Destination (
            Join-Path $nativeDirectory $addon.Name
        ) -Force
    }
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "OMP fork manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or
    $manifest.baseCommit -notmatch '^[0-9a-f]{40}$' -or
    [string]::IsNullOrWhiteSpace($manifest.repository) -or
    [string]::IsNullOrWhiteSpace($manifest.branch)) {
    throw 'OMP fork manifest is invalid.'
}

$patchPath = (Resolve-Path -LiteralPath (
    Join-Path (Split-Path -Parent $manifestPath) $manifest.patch
)).Path
$patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash
if ($patchHash -ne $manifest.patchSha256) {
    throw "OMP fork patch hash mismatch: expected $($manifest.patchSha256), got $patchHash"
}

if (-not $ForceRebuild -and (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf)) {
    try {
        $state = Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
        if ($state.baseCommit -eq $manifest.baseCommit -and
            $state.patchSha256 -eq $patchHash -and
            (Test-Path -LiteralPath $state.executable -PathType Leaf)) {
            $installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $state.executable).Hash
            if ($installedHash -eq $state.binarySha256) {
                Write-Output "OMP fork already installed: $($state.executable)"
                return
            }
        }
    } catch {
        Write-Warning "Ignoring stale OMP fork runtime state: $($_.Exception.Message)"
    }
}

$gitExecutable = Resolve-ApplicationPath 'git'
$bunExecutable = Resolve-ApplicationPath 'bun'
$bunVersionText = (& $bunExecutable --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read Bun version: $bunVersionText"
}
try {
    $bunVersion = [version]$bunVersionText
    $minimumBunVersion = [version]$manifest.minimumBunVersion
} catch {
    throw "Unable to compare Bun versions: installed=$bunVersionText required=$($manifest.minimumBunVersion)"
}
if ($bunVersion -lt $minimumBunVersion) {
    throw "Bun $($manifest.minimumBunVersion) or newer is required; found $bunVersionText."
}

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $repoRoot 'run/oh-my-pi-fork'
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)

if (-not (Test-Path -LiteralPath $SourceDirectory)) {
    $sourceParent = Split-Path -Parent $SourceDirectory
    New-Item -ItemType Directory -Path $sourceParent -Force | Out-Null
    Invoke-CheckedCommand $gitExecutable @(
        'clone',
        '--filter=blob:none',
        '--no-checkout',
        '--branch', $manifest.branch,
        $manifest.repository,
        $SourceDirectory
    ) $sourceParent
    Invoke-CheckedCommand $gitExecutable @(
        '-C', $SourceDirectory,
        'checkout', '--detach', $manifest.baseCommit
    ) $sourceParent
}

if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory '.git'))) {
    throw "OMP fork source is not a Git checkout: $SourceDirectory"
}
$sourceCommit = (& $gitExecutable -C $SourceDirectory rev-parse HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne $manifest.baseCommit) {
    throw "OMP fork source must be at $($manifest.baseCommit); found $sourceCommit"
}

$patchAlreadyApplied = Test-GitPatch $gitExecutable $SourceDirectory $patchPath -Reverse
if (-not $patchAlreadyApplied) {
    if (-not (Test-GitPatch $gitExecutable $SourceDirectory $patchPath)) {
        throw 'OMP fork patch is neither cleanly applicable nor already applied; refusing a partial update.'
    }
    Invoke-CheckedCommand $gitExecutable @(
        '-C', $SourceDirectory,
        'apply', '--whitespace=nowarn', $patchPath
    ) $repoRoot
}

if (-not (Test-GitPatch $gitExecutable $SourceDirectory $patchPath -Reverse)) {
    throw 'OMP fork patch verification failed after application.'
}

Invoke-CheckedCommand $bunExecutable @('install', '--frozen-lockfile') $SourceDirectory
Install-PublishedNativeAddon $bunExecutable $SourceDirectory (Join-Path $repoRoot 'run')
Invoke-CheckedCommand $bunExecutable @('audit') $SourceDirectory
if (-not $SkipValidation) {
    Invoke-CheckedCommand $bunExecutable @(
        'test', 'packages/agent/test/agent-loop.test.ts'
    ) $SourceDirectory
    Invoke-CheckedCommand $bunExecutable @(
        'test',
        'packages/coding-agent/test/agent-session-retry-cap.test.ts'
    ) $SourceDirectory
    Invoke-CheckedCommand $bunExecutable @(
        'test',
        'packages/coding-agent/test/tools/ask.test.ts',
        'packages/coding-agent/test/ask-timeout.test.ts'
    ) $SourceDirectory
    Invoke-CheckedCommand $bunExecutable @(
        'test',
        'packages/coding-agent/test/model-registry-command-values.test.ts'
    ) $SourceDirectory
    Invoke-CheckedCommand $bunExecutable @(
        'test',
        'packages/coding-agent/test/main-model-scope-notification.test.ts',
        '--test-name-pattern', 'resolveScopedModels'
    ) $SourceDirectory
    Invoke-CheckedCommand $bunExecutable @(
        'test',
        'packages/coding-agent/test/selector-settings-side-effects.test.ts',
        '--test-name-pattern', 'waits for background model discovery'
    ) $SourceDirectory
    Invoke-CheckedCommand $bunExecutable @('run', 'check') (
        Join-Path $SourceDirectory 'packages/agent'
    )
    Invoke-CheckedCommand $bunExecutable @('run', 'check') (
        Join-Path $SourceDirectory 'packages/coding-agent'
    )
}

$codingAgentDirectory = Join-Path $SourceDirectory 'packages/coding-agent'
Invoke-CheckedCommand $bunExecutable @('run', 'build') $codingAgentDirectory
$runningOnWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
$builtBinaryName = if ($runningOnWindows) { 'omp.exe' } else { 'omp' }
$builtBinary = Join-Path $codingAgentDirectory "dist/$builtBinaryName"
if (-not (Test-Path -LiteralPath $builtBinary -PathType Leaf)) {
    throw "OMP build did not produce the expected binary: $builtBinary"
}
$binaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $builtBinary).Hash

$bunBinDirectory = (& $bunExecutable pm bin -g 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($bunBinDirectory)) {
    $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $bunBinDirectory = Join-Path $userHome '.bun/bin'
}
New-Item -ItemType Directory -Path $bunBinDirectory -Force | Out-Null
$binarySuffix = $binaryHash.Substring(0, 12).ToLowerInvariant()
$installedName = if ($runningOnWindows) {
    "omp-fork-omp-config-$binarySuffix.exe"
} else {
    "omp-fork-omp-config-$binarySuffix"
}
$installedExecutable = Join-Path $bunBinDirectory $installedName
if (Test-Path -LiteralPath $installedExecutable -PathType Leaf) {
    $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedExecutable).Hash
    if ($existingHash -ne $binaryHash) {
        throw "Content-addressed OMP binary has an unexpected hash: $installedExecutable"
    }
} else {
    Copy-Item -LiteralPath $builtBinary -Destination $installedExecutable
}

$installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedExecutable).Hash
if ($installedHash -ne $binaryHash) {
    throw 'Installed OMP fork binary does not match the verified build.'
}

$runtimeDirectory = Split-Path -Parent $runtimeStatePath
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$runtimeState = [ordered]@{
    schemaVersion = 1
    executable = $installedExecutable
    repository = $manifest.repository
    branch = $manifest.branch
    baseCommit = $manifest.baseCommit
    patchSha256 = $patchHash
    binarySha256 = $binaryHash
    sourceDirectory = $SourceDirectory
}
$runtimeJson = $runtimeState | ConvertTo-Json -Depth 4
$temporaryState = "$runtimeStatePath.tmp-$PID"
[IO.File]::WriteAllText(
    $temporaryState,
    $runtimeJson + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)
Move-Item -LiteralPath $temporaryState -Destination $runtimeStatePath -Force

Write-Output "OMP fork source: $SourceDirectory"
Write-Output "OMP fork patch: $patchHash"
Write-Output "OMP fork installed: $installedExecutable"
