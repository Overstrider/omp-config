[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$bunCommand = Get-Command bun -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $bunCommand) {
    throw 'Bun is required to validate the vendored OMP Pantheon.'
}

Push-Location $repoRoot
try {
    # Real Git operations can exceed Bun's 5-second default on Windows when
    # antivirus or filesystem indexing is active. Keep a bounded timeout while
    # avoiding false negatives in the integration lifecycle tests.
    & $bunCommand.Path test --timeout 30000 `
        'agent/skills/evalfly/test' `
        'agent/skills/docs/test' `
        'agent/skills/latest-docs/test' `
        'agent/skills/linear/test'
    if ($LASTEXITCODE -ne 0) {
        throw 'OMP Pantheon test suites failed.'
    }

    $extensionRoot = Join-Path $repoRoot 'agent/extensions/oh-my-omp'
    & $bunCommand.Path install --cwd $extensionRoot --frozen-lockfile
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to restore OMP Pantheon extension development dependencies.'
    }
    & $bunCommand.Path audit --cwd $extensionRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'OMP Pantheon extension dependency vulnerability audit failed.'
    }

    Push-Location $extensionRoot
    try {
        & $bunCommand.Path run typecheck
        if ($LASTEXITCODE -ne 0) {
            throw 'OMP Pantheon extension typecheck failed.'
        }
    } finally {
        Pop-Location
    }

    Write-Output 'OMP Pantheon tests and extension typecheck passed.'
} finally {
    Pop-Location
}
