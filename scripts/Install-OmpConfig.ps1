[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'OmpConfig.Security.ps1')

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$agentDir = Join-Path $repoRoot 'agent'
$configName = '.omp'
$userHome = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::UserProfile
)
if ([string]::IsNullOrWhiteSpace($userHome)) {
    throw 'Unable to determine the current user home directory.'
}
$configAlias = Join-Path $userHome $configName
$runningOnWindows = [IO.Path]::DirectorySeparatorChar -eq '\'
if (-not (Test-Path -LiteralPath (Join-Path $agentDir 'config.yml'))) {
    throw "OMP agent config not found: $agentDir"
}

$routerSettings = Get-OmpRouterSettings -UseLegacyUserEnvironment
$merlinKey = Assert-OmpRouterApiKey ([string]$routerSettings.apiKey)
$merlinBaseUrl = Assert-OmpRouterBaseUrl ([string]$routerSettings.baseUrl)

if (Test-Path -LiteralPath $configAlias) {
    $existing = Get-Item -LiteralPath $configAlias -Force
    $isLink = [bool]($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if (-not $isLink) {
        throw "Refusing to replace a real directory: $configAlias"
    }
    $target = @($existing.Target)[0]
    if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $existing.Parent.FullName $target
    }
    if ([IO.Path]::GetFullPath($target) -ne $repoRoot) {
        throw "Existing config alias points elsewhere: $configAlias -> $target"
    }
} else {
    $linkType = if ($runningOnWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path $configAlias -Target $repoRoot | Out-Null
}

$forkInstaller = Join-Path $repoRoot 'scripts/Install-OmpFork.ps1'
& $forkInstaller
$runtimeStatePath = Join-Path $repoRoot 'run/omp-fork-runtime.json'
if (-not (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf)) {
    throw "OMP fork installer did not write runtime state: $runtimeStatePath"
}
$forkRuntime = Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
$ompForkExecutable = (Resolve-Path -LiteralPath $forkRuntime.executable).Path
$ompBinDirectory = (Resolve-Path -LiteralPath (
    Split-Path -Parent $ompForkExecutable
)).Path
$routerValueScript = Join-Path $repoRoot 'scripts/Get-OmpRouterValue.ps1'
if (-not (Test-Path -LiteralPath $routerValueScript -PathType Leaf)) {
    throw "OMP router value helper is missing: $routerValueScript"
}

if ($runningOnWindows) {
    $routerHelperPath = Join-Path $ompBinDirectory 'omp-config-router-value.cmd'
    $routerHelperContent = @'
@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -File "%USERPROFILE%\.omp\scripts\Get-OmpRouterValue.ps1" %*
'@
} else {
    $routerHelperPath = Join-Path $ompBinDirectory 'omp-config-router-value'
    $routerHelperContent = @'
#!/usr/bin/env sh
exec pwsh -NoLogo -NoProfile -NonInteractive -File "$HOME/.omp/scripts/Get-OmpRouterValue.ps1" "$@"
'@
    $routerHelperContent = $routerHelperContent.Replace("`r`n", "`n")
}
$routerHelperNewLine = if ($runningOnWindows) { "`r`n" } else { "`n" }
if (Test-Path -LiteralPath $routerHelperPath) {
    $existingRouterHelper = Get-Item -LiteralPath $routerHelperPath -Force
    if ($existingRouterHelper.PSIsContainer -or
        [bool]($existingRouterHelper.Attributes -band (
            [IO.FileAttributes]::ReparsePoint
        ))) {
        throw "Refusing to overwrite an unsafe router helper path: $routerHelperPath"
    }
}
[IO.File]::WriteAllText(
    $routerHelperPath,
    $routerHelperContent.TrimStart() + $routerHelperNewLine,
    [Text.UTF8Encoding]::new($false)
)
if (-not $runningOnWindows) {
    $chmodCommand = Get-Command chmod -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    & $chmodCommand.Path '700' $routerHelperPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to make the router value helper executable.'
    }
}

$pathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
if ($ompBinDirectory -notin $pathEntries) {
    $env:PATH = $ompBinDirectory + [IO.Path]::PathSeparator + $env:PATH
}

if ($runningOnWindows) {
    Write-OmpWindowsRouterSettings -ApiKey $merlinKey -BaseUrl $merlinBaseUrl
    # Migrate legacy plaintext user variables after the protected store exists.
    [Environment]::SetEnvironmentVariable('MERLIN_9ROUTER_API_KEY', $null, 'User')
    [Environment]::SetEnvironmentVariable('MERLIN_9ROUTER_BASE_URL', $null, 'User')
    [Environment]::SetEnvironmentVariable('PI_CONFIG_DIR', $configName, 'User')
    [Environment]::SetEnvironmentVariable('PI_CODING_AGENT_DIR', $null, 'User')
    [Environment]::SetEnvironmentVariable('PI_CONFIG_FILES', $null, 'User')
    [Environment]::SetEnvironmentVariable('OMP_SKIP_SETUP', '1', 'User')

    # Every shell must resolve `omp` to the fork. PATHEXT resolves .COM before
    # .EXE, so an omp.com copy safely shadows a running/upstream omp.exe in the
    # same directory without modifying or terminating existing processes.
    $ompApplication = Join-Path $ompBinDirectory 'omp.com'
    $forkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (
        $ompForkExecutable
    )).Hash
    $applicationHash = if (Test-Path -LiteralPath $ompApplication) {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $ompApplication).Hash
    } else {
        $null
    }
    if ($applicationHash -ne $forkHash) {
        Copy-Item -LiteralPath $ompForkExecutable -Destination (
            $ompApplication
        ) -Force
    }
}

$env:PI_CONFIG_DIR = $configName
$env:PI_CODING_AGENT_DIR = $agentDir
$env:MERLIN_9ROUTER_API_KEY = $merlinKey
$env:MERLIN_9ROUTER_BASE_URL = $merlinBaseUrl
$env:OMP_SKIP_SETUP = '1'
Remove-Item Env:PI_CONFIG_FILES -ErrorAction SilentlyContinue

$bunCommand = Get-Command bun -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $bunCommand) {
    throw 'Bun is required to restore the versioned OMP dependencies.'
}
foreach ($dependencyRoot in @($agentDir, (Join-Path $repoRoot 'plugins'))) {
    & $bunCommand.Path install --cwd $dependencyRoot --frozen-lockfile
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to restore OMP dependencies in: $dependencyRoot"
    }
    & $bunCommand.Path audit --cwd $dependencyRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency vulnerability audit failed in: $dependencyRoot"
    }
}

$launcherPath = Join-Path $repoRoot 'scripts/Invoke-Omp.ps1'
$launcherBlock = @'
# BEGIN omp-config launcher
function omp {
    $ompConfigRoot = Join-Path ([Environment]::GetFolderPath(
        [Environment+SpecialFolder]::UserProfile
    )) '.omp'
    & (Join-Path $ompConfigRoot 'scripts/Invoke-Omp.ps1') @args
}
# END omp-config launcher
'@
$launcherPattern = '(?ms)^# BEGIN omp-config launcher\r?\n.*?^# END omp-config launcher\r?\n?'
$profilePaths = @($PROFILE.CurrentUserCurrentHost) | Select-Object -Unique
foreach ($profilePath in $profilePaths) {
    $profileDirectory = Split-Path -Parent $profilePath
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    $profileContent = if (Test-Path -LiteralPath $profilePath) {
        Get-Content -LiteralPath $profilePath -Raw
    } else {
        ''
    }
    if ($profileContent -match $launcherPattern) {
        $profileContent = [regex]::Replace(
            $profileContent,
            $launcherPattern,
            $launcherBlock
        )
    } else {
        $profileContent = $profileContent.TrimEnd() + (
            [Environment]::NewLine * 2
        ) + $launcherBlock
    }
    [IO.File]::WriteAllText(
        $profilePath,
        $profileContent,
        [Text.UTF8Encoding]::new($false)
    )
}

$resolvedAgentDir = (& $launcherPath config path 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "omp config path failed: $resolvedAgentDir"
}

Write-Output "OMP config root: $configAlias -> $repoRoot"
Write-Output "OMP agent dir: $resolvedAgentDir"
if ($runningOnWindows) {
    Write-Output "OMP universal command: $ompApplication shadows omp.exe"
}
Write-Output 'OMP Pantheon: installed from the vendored, commit-pinned agent tree.'
foreach ($profilePath in $profilePaths) {
    Write-Output "OMP PowerShell launcher: $profilePath"
}
Write-Output 'OMP configuration installed for the current clone and user.'
