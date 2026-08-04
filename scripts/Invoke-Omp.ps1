$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'OmpConfig.Security.ps1')

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$agentDir = Join-Path $repoRoot 'agent'
$runtimeStatePath = Join-Path $repoRoot 'run/omp-fork-runtime.json'
$ompExecutable = $null
if (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf) {
    try {
        $runtimeState = Get-Content -LiteralPath $runtimeStatePath -Raw |
            ConvertFrom-Json
        if (Test-Path -LiteralPath $runtimeState.executable -PathType Leaf) {
            $ompExecutable = $runtimeState.executable
        }
    } catch {
        $ompExecutable = $null
    }
}
if ([string]::IsNullOrWhiteSpace($ompExecutable)) {
    $ompCommand = Get-Command omp-fork -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $ompCommand) {
        throw 'OMP fork is not installed. Run scripts/Install-OmpFork.ps1 first.'
    }
    $ompExecutable = if ($ompCommand.Path) {
        $ompCommand.Path
    } else {
        $ompCommand.Source
    }
}

$routerSettings = Get-OmpRouterSettings -UseLegacyUserEnvironment
$merlinKey = Assert-OmpRouterApiKey ([string]$routerSettings.apiKey)
$merlinBaseUrl = Assert-OmpRouterBaseUrl ([string]$routerSettings.baseUrl)

# Set these for every invocation, including PowerShell windows opened before
# the persistent environment variables were configured.
$env:PI_CONFIG_DIR = '.omp'
$env:PI_CODING_AGENT_DIR = $agentDir
$env:MERLIN_9ROUTER_API_KEY = $merlinKey
$env:MERLIN_9ROUTER_BASE_URL = $merlinBaseUrl
$env:OMP_SKIP_SETUP = '1'
Remove-Item Env:PI_CONFIG_FILES -ErrorAction SilentlyContinue

$forwardedArgs = @($args)
if ($forwardedArgs.Count -gt 0 -and $forwardedArgs[0] -eq '.') {
    if ($forwardedArgs.Count -gt 1) {
        $forwardedArgs = @('--cwd', (Get-Location).Path) + @(
            $forwardedArgs[1..($forwardedArgs.Count - 1)]
        )
    } else {
        $forwardedArgs = @('--cwd', (Get-Location).Path)
    }
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & $ompExecutable @forwardedArgs
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
