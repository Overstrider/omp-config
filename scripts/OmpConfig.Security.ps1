function Test-OmpRunningOnWindows {
    return [IO.Path]::DirectorySeparatorChar -eq '\'
}

function Assert-OmpRouterApiKey {
    param([Parameter(Mandatory)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value -ne $Value.Trim() -or
        $Value.IndexOfAny([char[]]@("`0", "`r", "`n")) -ge 0) {
        throw 'The router API key is invalid.'
    }
    return $Value
}

function Assert-OmpRouterBaseUrl {
    param([Parameter(Mandatory)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value -ne $Value.Trim() -or
        $Value.IndexOfAny([char[]]@("`0", "`r", "`n")) -ge 0) {
        throw 'The router base URL is invalid.'
    }

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne [Uri]::UriSchemeHttps -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment) -or
        $uri.HostNameType -ne [UriHostNameType]::Dns) {
        throw 'The router base URL must be a public HTTPS DNS URL without credentials, query, or fragment.'
    }

    $hostName = $uri.DnsSafeHost.ToLowerInvariant()
    $blockedHostSuffixes = @(
        'localhost',
        '.localhost',
        '.local',
        '.internal',
        '.lan',
        '.home',
        '.test',
        '.invalid',
        '.example'
    )
    if (-not $hostName.Contains('.') -or
        @($blockedHostSuffixes | Where-Object {
            $hostName -eq $_ -or $hostName.EndsWith($_)
        }).Count -gt 0) {
        throw 'The router base URL must not target a local or reserved hostname.'
    }

    return $uri.AbsoluteUri.TrimEnd('/')
}

function Get-OmpRouterStorePath {
    if (-not (Test-OmpRunningOnWindows)) {
        return $null
    }
    $localDataPath = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData
    )
    if ([string]::IsNullOrWhiteSpace($localDataPath)) {
        throw 'Unable to determine the local application data directory.'
    }
    return Join-Path $localDataPath 'omp-config/router-settings.dpapi'
}

function Import-OmpDataProtection {
    if (-not ('System.Security.Cryptography.ProtectedData' -as [type])) {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
    }
    if (-not ('System.Security.Cryptography.ProtectedData' -as [type])) {
        throw 'Windows data protection is unavailable.'
    }
}

function Read-OmpWindowsRouterSettings {
    if (-not (Test-OmpRunningOnWindows)) {
        return $null
    }
    $storePath = Get-OmpRouterStorePath
    if (-not (Test-Path -LiteralPath $storePath -PathType Leaf)) {
        return $null
    }
    $storeItem = Get-Item -LiteralPath $storePath -Force
    if ([bool]($storeItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Stored router settings use an unsafe filesystem link.'
    }

    $plainBytes = $null
    try {
        Import-OmpDataProtection
        $protectedText = Get-Content -LiteralPath $storePath -Raw
        $protectedBytes = [Convert]::FromBase64String($protectedText.Trim())
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $payload = [Text.Encoding]::UTF8.GetString($plainBytes) |
            ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($payload.apiKey) -or
            [string]::IsNullOrWhiteSpace($payload.baseUrl)) {
            throw 'Incomplete router settings.'
        }
        return [pscustomobject]@{
            apiKey = [string]$payload.apiKey
            baseUrl = [string]$payload.baseUrl
        }
    } catch {
        throw 'Stored router settings cannot be decrypted. Rerun the installer with fresh settings.'
    } finally {
        if ($plainBytes) {
            [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
    }
}

function Write-OmpWindowsRouterSettings {
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [Parameter(Mandatory)][string]$BaseUrl
    )

    if (-not (Test-OmpRunningOnWindows)) {
        return
    }
    $validatedKey = Assert-OmpRouterApiKey $ApiKey
    $validatedUrl = Assert-OmpRouterBaseUrl $BaseUrl
    $storePath = Get-OmpRouterStorePath
    $storeDirectory = Split-Path -Parent $storePath
    New-Item -ItemType Directory -Path $storeDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $storePath) {
        $storeItem = Get-Item -LiteralPath $storePath -Force
        if ($storeItem.PSIsContainer -or
            [bool]($storeItem.Attributes -band (
                [IO.FileAttributes]::ReparsePoint
            ))) {
            throw 'Refusing to overwrite an unsafe router settings path.'
        }
    }

    $payloadBytes = $null
    try {
        Import-OmpDataProtection
        $payload = [ordered]@{
            schemaVersion = 1
            apiKey = $validatedKey
            baseUrl = $validatedUrl
        } | ConvertTo-Json -Compress
        $payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $payloadBytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $temporaryPath = "$storePath.tmp-$PID"
        if (Test-Path -LiteralPath $temporaryPath) {
            throw 'Temporary router settings path already exists.'
        }
        [IO.File]::WriteAllText(
            $temporaryPath,
            [Convert]::ToBase64String($protectedBytes) + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false)
        )
        Move-Item -LiteralPath $temporaryPath -Destination $storePath -Force
    } finally {
        if ($payloadBytes) {
            [Array]::Clear($payloadBytes, 0, $payloadBytes.Length)
        }
    }
}

function Get-OmpRouterSettings {
    param([switch]$UseLegacyUserEnvironment)

    $apiKey = [Environment]::GetEnvironmentVariable(
        'MERLIN_9ROUTER_API_KEY',
        'Process'
    )
    $baseUrl = [Environment]::GetEnvironmentVariable(
        'MERLIN_9ROUTER_BASE_URL',
        'Process'
    )

    if (Test-OmpRunningOnWindows) {
        $stored = $null
        if ([string]::IsNullOrWhiteSpace($apiKey) -or
            [string]::IsNullOrWhiteSpace($baseUrl)) {
            $stored = Read-OmpWindowsRouterSettings
        }
        if ([string]::IsNullOrWhiteSpace($apiKey) -and $stored) {
            $apiKey = $stored.apiKey
        }
        if ([string]::IsNullOrWhiteSpace($baseUrl) -and $stored) {
            $baseUrl = $stored.baseUrl
        }
        if ($UseLegacyUserEnvironment) {
            if ([string]::IsNullOrWhiteSpace($apiKey)) {
                $apiKey = [Environment]::GetEnvironmentVariable(
                    'MERLIN_9ROUTER_API_KEY',
                    'User'
                )
            }
            if ([string]::IsNullOrWhiteSpace($baseUrl)) {
                $baseUrl = [Environment]::GetEnvironmentVariable(
                    'MERLIN_9ROUTER_BASE_URL',
                    'User'
                )
            }
        }
    }

    return [pscustomobject]@{
        apiKey = $apiKey
        baseUrl = $baseUrl
    }
}
