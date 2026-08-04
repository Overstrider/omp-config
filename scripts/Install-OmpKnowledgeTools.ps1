[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$codebaseMemoryVersion = '0.9.0'
$graphifyVersion = '0.9.31'

function Add-PathEntry {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }
    $separatorPattern = [regex]::Escape([string][IO.Path]::PathSeparator)
    $entries = @($env:PATH -split $separatorPattern)
    if ($entries -notcontains $Path) {
        $env:PATH = $Path + [IO.Path]::PathSeparator + $env:PATH
    }
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    & npm install --global "codebase-memory-mcp@$codebaseMemoryVersion"
} elseif (Get-Command bun -ErrorAction SilentlyContinue) {
    & bun install --global "codebase-memory-mcp@$codebaseMemoryVersion"
} else {
    throw 'npm or Bun is required to install codebase-memory-mcp.'
}
if ($LASTEXITCODE -ne 0) {
    throw 'codebase-memory-mcp installation failed.'
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmPrefix = (& npm prefix --global 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) {
        Add-PathEntry $npmPrefix
        Add-PathEntry (Join-Path $npmPrefix 'bin')
    }
}
if (Get-Command bun -ErrorAction SilentlyContinue) {
    $bunRoot = if ($env:BUN_INSTALL) {
        $env:BUN_INSTALL
    } else {
        Join-Path ([Environment]::GetFolderPath(
            [Environment+SpecialFolder]::UserProfile
        )) '.bun'
    }
    Add-PathEntry (Join-Path $bunRoot 'bin')
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw 'uv is required. Install it from https://docs.astral.sh/uv/.'
}

& uv tool install --force --python 3.11 "graphifyy[mcp]==$graphifyVersion"
if ($LASTEXITCODE -ne 0) {
    throw 'Graphify installation failed.'
}

$uvToolBin = (& uv tool dir --bin 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -eq 0) {
    Add-PathEntry $uvToolBin
}

& codebase-memory-mcp config set auto_index true
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enable codebase-memory-mcp auto_index.'
}
& codebase-memory-mcp config set auto_watch true
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enable codebase-memory-mcp auto_watch.'
}

$codebaseMemoryActual = (& codebase-memory-mcp --version 2>&1 | Out-String).Trim()
if ($codebaseMemoryActual -notmatch [regex]::Escape($codebaseMemoryVersion)) {
    throw "Unexpected codebase-memory-mcp version: $codebaseMemoryActual"
}

$uvToolList = (& uv tool list 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to inspect the installed uv tools.'
}
$graphifyMatch = [regex]::Match($uvToolList, '(?m)^graphifyy v(?<version>\S+)\s*$')
if (-not $graphifyMatch.Success) {
    throw 'Unable to determine the Graphify version.'
}
$graphifyInstalledVersion = $graphifyMatch.Groups['version'].Value
if ($graphifyInstalledVersion -ne $graphifyVersion) {
    throw "Unexpected Graphify version: $graphifyInstalledVersion"
}
$graphifyActual = "graphify $graphifyInstalledVersion"
& graphify-mcp --help *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'graphify-mcp is not runnable.'
}

Write-Output "Codebase Memory: $codebaseMemoryActual"
Write-Output "Graphify: $graphifyActual"
Write-Output 'OMP MCP configuration is versioned in agent/mcp.json.'
