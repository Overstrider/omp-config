[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('api-key', 'base-url')]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'OmpConfig.Security.ps1')

$settings = Get-OmpRouterSettings -UseLegacyUserEnvironment
$value = if ($Name -eq 'api-key') {
    Assert-OmpRouterApiKey ([string]$settings.apiKey)
} else {
    Assert-OmpRouterBaseUrl ([string]$settings.baseUrl)
}
[Console]::Out.Write($value)
