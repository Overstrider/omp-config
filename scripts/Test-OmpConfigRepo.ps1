[CmdletBinding()]
param(
    [switch]$Installed,
    [switch]$SkipRouterDiscovery
)

$ErrorActionPreference = 'Stop'

if ($SkipRouterDiscovery -and -not $Installed) {
    throw '-SkipRouterDiscovery is valid only with -Installed.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    $mcpConfig = Get-Content -LiteralPath 'agent/mcp.json' -Raw | ConvertFrom-Json
    $pluginPackage = Get-Content -LiteralPath 'plugins/package.json' -Raw | ConvertFrom-Json
    Get-Content -LiteralPath 'agent/skills/upstream-lock.json' -Raw | ConvertFrom-Json | Out-Null
    $agentPackage = Get-Content -LiteralPath 'agent/package.json' -Raw | ConvertFrom-Json
    $pantheonLock = Get-Content -LiteralPath 'agent/pantheon/upstream-lock.json' -Raw | ConvertFrom-Json
    $pantheonExtensionPackage = Get-Content -LiteralPath (
        'agent/extensions/oh-my-omp/package.json'
    ) -Raw | ConvertFrom-Json
    $forkManifest = Get-Content -LiteralPath 'fork/manifest.json' -Raw | ConvertFrom-Json

    if ($forkManifest.schemaVersion -ne 1 -or
        $forkManifest.repository -ne 'https://github.com/Overstrider/oh-my-pi.git' -or
        $forkManifest.branch -ne 'feat/kimi-harness-merlin-9router' -or
        $forkManifest.baseCommit -notmatch '^[0-9a-f]{40}$') {
        throw 'The OMP fork manifest is invalid.'
    }
    $forkPatchPath = Join-Path 'fork' $forkManifest.patch
    if (-not (Test-Path -LiteralPath $forkPatchPath -PathType Leaf)) {
        throw "The OMP fork patch is missing: $forkPatchPath"
    }
    $forkPatchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $forkPatchPath).Hash
    if ($forkPatchHash -ne $forkManifest.patchSha256) {
        throw 'The OMP fork patch does not match manifest.json.'
    }
    $forkPatchContent = Get-Content -LiteralPath $forkPatchPath -Raw
    foreach ($secureOverride in @(
        '"adm-zip": "0.6.0"',
        '"sharp": "0.35.3"',
        '"tar": "7.5.22"'
    )) {
        if (-not $forkPatchContent.Contains($secureOverride)) {
            throw "Required fork dependency security override is missing: $secureOverride"
        }
    }
    foreach ($feature in @(
        'kimi-k3-merlin-harness',
        'cursor-grok-stream-recovery',
        'cursor-completed-tool-idempotency',
        'cursor-merlin-model-discovery',
        'ask-recommended-timeout-in-plan-mode',
        'private-router-runtime-values',
        'audited-transitive-dependencies'
    )) {
        if ($feature -notin @($forkManifest.features)) {
            throw "Required OMP fork feature is missing: $feature"
        }
    }
    $patchedFiles = @(git apply --numstat $forkPatchPath | ForEach-Object {
        ($_ -split "`t")[-1]
    })
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect the OMP fork patch.'
    }
    foreach ($patchedFile in @(
        'bun.lock',
        'package.json',
        'packages/agent/src/agent-loop.ts',
        'packages/agent/test/agent-loop.test.ts',
        'packages/coding-agent/src/config/model-registry.ts',
        'packages/coding-agent/src/main.ts',
        'packages/coding-agent/src/modes/controllers/selector-controller.ts',
        'packages/coding-agent/src/tools/ask.ts',
        'packages/coding-agent/test/model-registry-command-values.test.ts',
        'packages/coding-agent/test/tools/ask.test.ts'
    )) {
        if ($patchedFile -notin $patchedFiles) {
            throw "Required runtime fix is absent from the fork patch: $patchedFile"
        }
    }
    foreach ($requiredScript in @(
        'scripts/Install-OmpFork.ps1',
        'scripts/Install-OmpConfig.ps1',
        'scripts/Invoke-Omp.ps1',
        'scripts/Get-OmpRouterValue.ps1',
        'scripts/OmpConfig.Security.ps1',
        'scripts/Test-OmpPantheon.ps1'
    )) {
        if (-not (Test-Path -LiteralPath $requiredScript -PathType Leaf)) {
            throw "Required OMP installer is missing: $requiredScript"
        }
    }

    if ($pantheonLock.name -ne 'omp-pantheon' -or
        $pantheonLock.commit -notmatch '^[0-9a-f]{40}$' -or
        $pantheonLock.installation -ne 'vendored') {
        throw 'The OMP Pantheon source lock is invalid.'
    }
    foreach ($dependency in @('@linear/sdk', 'turndown', 'typebox')) {
        if (-not $agentPackage.dependencies.PSObject.Properties[$dependency]) {
            throw "Required Pantheon runtime dependency is missing: $dependency"
        }
    }
    if ($pluginPackage.dependencies.'@mariozechner/pi-ai' -ne
            'npm:@oh-my-pi/pi-ai@17.2.8' -or
        $pluginPackage.dependencies.'@mariozechner/pi-coding-agent' -ne
            'npm:@oh-my-pi/pi-coding-agent@17.2.8') {
        throw 'Cursor plugin compatibility peers are not pinned to the audited OMP packages.'
    }
    foreach ($package in @($pluginPackage, $pantheonExtensionPackage)) {
        foreach ($secureOverride in (@{
            'adm-zip' = '0.6.0'
            'sharp' = '0.35.3'
            'tar' = '7.5.22'
        }).GetEnumerator()) {
            if ($package.overrides.PSObject.Properties[$secureOverride.Key].Value -ne
                $secureOverride.Value) {
                throw "Dependency security override is missing: $($secureOverride.Key)"
            }
        }
    }
    if ($pantheonExtensionPackage.devDependencies.'@oh-my-pi/pi-coding-agent' -ne
            '17.2.8' -or
        $pantheonExtensionPackage.overrides.protobufjs -ne '7.6.5') {
        throw 'Pantheon development dependencies are not pinned to audited versions.'
    }
    foreach ($requiredPath in @(
        'agent/extensions/oh-my-omp/index.ts',
        'agent/agents/sisyphus.md',
        'agent/agents/atlas.md',
        'agent/commands/omomomo.md',
        'agent/commands/evalfly-enforce.md',
        'agent/skills/evalfly/README.md',
        'agent/skills/evaluation-flywheel/SKILL.md',
        'agent/skills/specsafe/SKILL.md',
        'agent/hooks/specsafe-session.ts',
        'agent/pantheon/ATTRIBUTION.md'
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required Pantheon asset is missing: $requiredPath"
        }
    }

    $modelsConfig = Get-Content -LiteralPath 'agent/models.yml' -Raw
    foreach ($requiredValue in @(
        'merlin-9router:',
        "baseUrl: '!omp-config-router-value base-url'",
        'api: openai-completions',
        "apiKey: '!omp-config-router-value api-key'",
        'authHeader: true',
        'type: proxy',
        'allowEmpty: false'
    )) {
        if (-not $modelsConfig.Contains($requiredValue)) {
            throw "Required Merlin model configuration is missing: $requiredValue"
        }
    }
    if ($modelsConfig -match '(?m)^\s*baseUrl:\s+["'']?https?://') {
        throw 'A literal provider endpoint is present in agent/models.yml.'
    }

    $agentConfig = Get-Content -LiteralPath 'agent/config.yml' -Raw
    if ($agentConfig -notmatch '(?m)^setupVersion:\s+1\s*$') {
        throw 'Interactive OMP setup is not marked complete.'
    }
    if ($agentConfig -notmatch '(?ms)^startup:\s*\r?\n\s+setupWizard:\s+false\s*$') {
        throw 'Interactive OMP setup wizard is not disabled.'
    }
    foreach ($enabledProvider in @('  - merlin-9router/**', '  - cursor/**')) {
        if (-not $agentConfig.Contains($enabledProvider)) {
            throw "Required enabledModels provider is missing: $enabledProvider"
        }
    }
    if ($agentConfig -notmatch '(?ms)^disabledProviders:\s*\r?\n\s+- openrouter\s*$') {
        throw 'The direct OpenRouter provider is not disabled.'
    }
    $requiredModelRoles = @{
        default = 'merlin-9router/cx/gpt-5.6-luna:max'
        slow = 'merlin-9router/cx/gpt-5.6-luna:max'
        vision = 'merlin-9router/cx/gpt-5.6-luna:max'
        plan = 'merlin-9router/cx/gpt-5.6-luna:max'
        designer = 'merlin-9router/cx/gpt-5.6-luna:max'
        commit = 'merlin-9router/cx/gpt-5.6-luna:max'
        tiny = 'merlin-9router/cx/gpt-5.6-luna:max'
        task = 'merlin-9router/cx/gpt-5.6-luna:max'
        advisor = 'merlin-9router/cx/gpt-5.6-luna:max'
        smol = 'merlin-9router/cx/gpt-5.6-luna:max'
    }
    foreach ($entry in $requiredModelRoles.GetEnumerator()) {
        $rolePattern = "(?m)^\s+$([regex]::Escape($entry.Key)):\s+$([regex]::Escape($entry.Value))\s*$"
        if ($agentConfig -notmatch $rolePattern) {
            throw "Required Merlin model role is missing: $($entry.Key)"
        }
    }
    foreach ($requiredInteractionSetting in @(
        '(?ms)^ask:\s*\r?\n\s+enabled:\s+false\s*\r?\n\s+timeout:\s+15\s*\r?\n\s+notify:\s+["'']?off["'']?\s*$',
        '(?ms)^tools:\s*\r?\n\s+approvalMode:\s+yolo\s*$'
    )) {
        if ($agentConfig -notmatch $requiredInteractionSetting) {
            throw "Required autonomous interaction setting is missing: $requiredInteractionSetting"
        }
    }

    $requiredSkills = @('caveman', 'graphify', 'ponytail')
    foreach ($skill in $requiredSkills) {
        $skillFile = "agent/skills/$skill/SKILL.md"
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            throw "Required default skill is missing: $skillFile"
        }
        $skillContent = Get-Content -LiteralPath $skillFile -Raw
        if ($skillContent -notmatch "(?m)^name:\s+$([regex]::Escape($skill))\s*$") {
            throw "Invalid skill name in: $skillFile"
        }
    }

    $easyExtensionPath = 'agent/extensions/easy.ts'
    $smolRole = [regex]::Match(
        $agentConfig,
        '(?m)^\s+smol:\s+(\S+)\s*$'
    )
    if (-not $smolRole.Success) {
        throw 'The smol model role used by /easy is not configured.'
    }
    $easyExtension = Get-Content -LiteralPath $easyExtensionPath -Raw
    foreach ($requiredValue in @(
        'registerCommand("easy"',
        'ctx.models.resolve("@smol")',
        'pi.setModel(model)',
        'pi.setThinkingLevel(thinking)',
        'pi.sendUserMessage(prompt)'
    )) {
        if (-not $easyExtension.Contains($requiredValue)) {
            throw "The /easy extension is incomplete: $requiredValue"
        }
    }

    $graphifyLock = Get-Content -LiteralPath 'agent/skills/upstream-lock.json' -Raw | ConvertFrom-Json
    $graphifyStamp = (Get-Content -LiteralPath 'agent/skills/graphify/.graphify_version' -Raw).Trim()
    if ($graphifyStamp -ne $graphifyLock.graphify.version) {
        throw 'The Graphify skill version stamp does not match upstream-lock.json.'
    }

    $requiredMcpServers = @{
        'codebase-memory-mcp' = 'codebase-memory-mcp'
        'graphify' = 'graphify-mcp'
    }
    foreach ($entry in $requiredMcpServers.GetEnumerator()) {
        $property = $mcpConfig.mcpServers.PSObject.Properties[$entry.Key]
        if (-not $property) {
            throw "Required MCP server is missing: $($entry.Key)"
        }
        if ($property.Value.command -ne $entry.Value -or $property.Value.enabled -ne $true) {
            throw "Invalid MCP server configuration: $($entry.Key)"
        }
    }

    $stickyRules = Get-Content -LiteralPath 'agent/RULES.md' -Raw
    foreach ($mode in @('Caveman `full`', 'Ponytail `full`')) {
        if (-not $stickyRules.Contains($mode)) {
            throw "Default mode missing from agent/RULES.md: $mode"
        }
    }

    $hephaestus = Get-Content -LiteralPath 'agent/agents/hephaestus.md' -Raw
    foreach ($requiredAutonomyRule in @(
        'Differences in effort, multiple valid implementations, uncertainty, or preference trade-offs are not reasons to ask the user.',
        'Do not stop to ask which implementation the user prefers when a defensible reversible choice exists.',
        'Never ask for preferences, confirmation, permission to do obvious work, or whether to proceed'
    )) {
        if (-not $hephaestus.Contains($requiredAutonomyRule)) {
            throw "Required Hephaestus autonomy rule is missing: $requiredAutonomyRule"
        }
    }

    $localAgentRules = Get-Content -LiteralPath 'AGENTS.md' -Raw
    foreach ($rulesContent in @($localAgentRules, $stickyRules)) {
        foreach ($requiredRule in @(
            'Never use Orca computer-use',
            'Use background CLI, shell commands, APIs, and non-interactive processes only.'
        )) {
            if (-not $rulesContent.Contains($requiredRule)) {
                throw "Required no-desktop rule is missing: $requiredRule"
            }
        }
    }

    $tracked = @(git ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate tracked files.'
    }

    $forbiddenPaths = @(
        '(^|/)\.env($|\.)',
        '(^|/)secrets\.ya?ml$',
        'secret-placeholder\.key$',
        '(^|/)agent\.db',
        '(^|/)sessions/',
        '(^|/)node_modules/',
        'omp-plugins\.lock\.json$'
    )
    foreach ($file in $tracked) {
        foreach ($pattern in $forbiddenPaths) {
            if ($file -match $pattern) {
                throw "Private/runtime path is tracked: $file"
            }
        }
    }

    $machineSpecificPatterns = @(
        '(?i)\b[A-Z]:[\\/]',
        '(?i)\\Users\\',
        '(?i)/Users/[^/<\s]+/',
        '(?i)/home/[^/<\s]+/',
        '(?i)\$env:(USERPROFILE|APPDATA|LOCALAPPDATA)',
        '(?i)OneDrive',
        '(?i)\.bun[\\/]bin[\\/]omp(?:\.exe)?'
    )
    foreach ($file in $tracked) {
        if ($file -eq 'scripts/Test-OmpConfigRepo.ps1' -or $file -match '^agent/skills/') {
            continue
        }
        $path = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $machineSpecificPatterns) {
            if ($content -match $pattern) {
                throw "Machine-specific path found in tracked file: $file"
            }
        }
    }

    $secretPatterns = @(
        '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?i)\bsk-[a-z0-9_-]{8,}\b',
        '(?i)\bghp_[a-z0-9]{20,}\b',
        '(?i)\b(api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*["''][^!$<{][^"'']{7,}'
    )
    foreach ($file in $tracked) {
        $path = Join-Path $repoRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern) {
                throw "Potential secret found in tracked file: $file"
            }
        }
    }

    if ($Installed) {
        . (Join-Path $repoRoot 'scripts/OmpConfig.Security.ps1')
        $routerSettings = Get-OmpRouterSettings -UseLegacyUserEnvironment
        [void](Assert-OmpRouterApiKey ([string]$routerSettings.apiKey))
        [void](Assert-OmpRouterBaseUrl ([string]$routerSettings.baseUrl))

        foreach ($dependencyPath in @(
            'agent/node_modules/@linear/sdk/package.json',
            'agent/node_modules/turndown/package.json',
            'agent/node_modules/typebox/package.json',
            'plugins/node_modules/@offbynan/pi-cursor-provider/package.json'
        )) {
            if (-not (Test-Path -LiteralPath $dependencyPath -PathType Leaf)) {
                throw "Pantheon runtime dependency is not installed: $dependencyPath"
            }
        }

        $expectedAgentDir = Join-Path $repoRoot 'agent'
        $launcherPath = Join-Path $repoRoot 'scripts/Invoke-Omp.ps1'
        if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
            throw "OMP PowerShell launcher is missing: $launcherPath"
        }
        $launcherConfigPath = (& $launcherPath config path 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $launcherConfigPath -ne $expectedAgentDir) {
            throw "OMP PowerShell launcher resolved the wrong config: $launcherConfigPath"
        }

        $runtimeStatePath = Join-Path $repoRoot 'run/omp-fork-runtime.json'
        if (-not (Test-Path -LiteralPath $runtimeStatePath -PathType Leaf)) {
            throw "OMP fork runtime state is missing: $runtimeStatePath"
        }
        $forkRuntime = Get-Content -LiteralPath $runtimeStatePath -Raw | ConvertFrom-Json
        $forkExecutable = (Resolve-Path -LiteralPath $forkRuntime.executable).Path
        $forkHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $forkExecutable).Hash
        if ($forkHash -ne $forkRuntime.binarySha256 -or
            $forkRuntime.patchSha256 -ne $forkManifest.patchSha256 -or
            $forkRuntime.baseCommit -ne $forkManifest.baseCommit) {
            throw 'Installed OMP fork runtime does not match the versioned manifest.'
        }

        if ([IO.Path]::DirectorySeparatorChar -eq '\') {
            $ompApplication = Join-Path (
                Split-Path -Parent $forkExecutable
            ) 'omp.com'
            if (-not (Test-Path -LiteralPath $ompApplication -PathType Leaf)) {
                throw "Universal OMP command is missing: $ompApplication"
            }
            $ompHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (
                $ompApplication
            )).Hash
            if ($forkHash -ne $ompHash) {
                throw 'omp.com does not resolve to the required omp-fork build.'
            }
        }

        $routerHelperName = if ([IO.Path]::DirectorySeparatorChar -eq '\') {
            'omp-config-router-value.cmd'
        } else {
            'omp-config-router-value'
        }
        $routerHelperPath = Join-Path (
            Split-Path -Parent $forkExecutable
        ) $routerHelperName
        if (-not (Test-Path -LiteralPath $routerHelperPath -PathType Leaf)) {
            throw "Router value helper is missing: $routerHelperPath"
        }

        if (-not $SkipRouterDiscovery) {
            $previousProcessKey = $env:MERLIN_9ROUTER_API_KEY
            $previousProcessBaseUrl = $env:MERLIN_9ROUTER_BASE_URL
            try {
                if ([IO.Path]::DirectorySeparatorChar -eq '\') {
                    # Windows must work from the DPAPI store even when no plaintext
                    # router setting exists in the process or user environment.
                    Remove-Item Env:MERLIN_9ROUTER_API_KEY -ErrorAction SilentlyContinue
                    Remove-Item Env:MERLIN_9ROUTER_BASE_URL -ErrorAction SilentlyContinue
                }
                $modelCommand = if ([IO.Path]::DirectorySeparatorChar -eq '\') {
                    $ompApplication
                } else {
                    $launcherPath
                }
                $nativeModels = (& $modelCommand models merlin-9router --json 2>&1 |
                    Out-String).Trim()
                if ($LASTEXITCODE -ne 0) {
                    throw "Configured OMP Merlin discovery failed: $nativeModels"
                }
                $modelResult = $nativeModels | ConvertFrom-Json
                if (@($modelResult.models).Count -eq 0) {
                    throw 'Configured OMP found no Merlin models.'
                }

                $allModelsJson = (& $modelCommand models --json 2>&1 | Out-String).Trim()
                if ($LASTEXITCODE -ne 0) {
                    throw "Configured OMP model discovery failed: $allModelsJson"
                }
                $allModels = $allModelsJson | ConvertFrom-Json
                $easySelector = $smolRole.Groups[1].Value -replace (
                    ':(off|minimal|low|medium|high|xhigh|max|auto)$'
                ), ''
                if (-not @($allModels.models | Where-Object {
                    $_.selector -eq $easySelector
                })) {
                    throw "The configured /easy model is unavailable: $easySelector"
                }
            } finally {
                if ([string]::IsNullOrWhiteSpace($previousProcessKey)) {
                    Remove-Item Env:MERLIN_9ROUTER_API_KEY -ErrorAction SilentlyContinue
                } else {
                    $env:MERLIN_9ROUTER_API_KEY = $previousProcessKey
                }
                if ([string]::IsNullOrWhiteSpace($previousProcessBaseUrl)) {
                    Remove-Item Env:MERLIN_9ROUTER_BASE_URL -ErrorAction SilentlyContinue
                } else {
                    $env:MERLIN_9ROUTER_BASE_URL = $previousProcessBaseUrl
                }
            }
        }
    }

    Write-Output 'OMP Git configuration checks passed.'
} finally {
    Pop-Location
}
