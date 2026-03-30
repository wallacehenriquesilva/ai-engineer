#Requires -Version 5.1
# install.ps1 — Setup completo do AI Engineer (Windows)
#
# Uso:
#   .\install.ps1              # interativo completo
#   .\install.ps1 -Skills      # apenas instala skills/commands
#   .\install.ps1 -Update      # atualiza para a versao mais recente

param(
    [switch]$Skills,
    [switch]$Update
)

$Version = "0.1.0"
$RepoUrl = if ($env:CA_AI_ENGINEER_REPO) { $env:CA_AI_ENGINEER_REPO } else { "https://github.com/wallacehenriquesilva/ai-engineer.git" }
$RepoBranch = if ($env:CA_AI_ENGINEER_BRANCH) { $env:CA_AI_ENGINEER_BRANCH } else { "main" }
$InstallDir = if ($env:CA_AI_ENGINEER_DIR) { $env:CA_AI_ENGINEER_DIR } else { "$HOME\.ai-engineer" }
$CleanupDir = $null
$TotalSteps = 7

# ── Cores ─────────────────────────────────────────────────────────────────

function Log-Ok    { param($msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Log-Warn  { param($msg) Write-Host "  ! $msg" -ForegroundColor Yellow }
function Log-Err   { param($msg) Write-Host "  ✗ $msg" -ForegroundColor Red }
function Log-Info  { param($msg) Write-Host "  → $msg" -ForegroundColor Cyan }
function Log-Step  { param($n, $msg) Write-Host "`n[$n/$TotalSteps] $msg" -ForegroundColor Cyan }
function Prompt-User { param($msg) Write-Host "  ? $msg " -ForegroundColor Cyan -NoNewline; return Read-Host }

# ── Resolve source ────────────────────────────────────────────────────────

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if ((Test-Path "$ScriptDir\skills") -and (Test-Path "$ScriptDir\commands")) {
    $SourceDir = $ScriptDir
} else {
    $TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "ai-engineer-$(Get-Random)"
    $CleanupDir = $TmpDir
    Write-Host "Baixando AI Engineer..." -ForegroundColor Cyan
    $null = git clone --depth 1 --branch $RepoBranch $RepoUrl $TmpDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Log-Err "Falha ao clonar $RepoUrl"
        exit 1
    }
    $SourceDir = $TmpDir
}

# ── Funcoes ───────────────────────────────────────────────────────────────

function Install-SkillsAndCommands {
    $destSkills = "$HOME\.claude\skills"
    $destCommands = "$HOME\.claude\commands"

    if (-not (Test-Path $destSkills)) { New-Item -ItemType Directory -Path $destSkills -Force | Out-Null }
    if (-not (Test-Path $destCommands)) { New-Item -ItemType Directory -Path $destCommands -Force | Out-Null }

    $count = 0
    Get-ChildItem -Path "$SourceDir\skills" -Directory | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination "$destSkills\$($_.Name)" -Recurse -Force
        $count++
    }
    Log-Ok "$count skills instaladas em $destSkills"

    $cmdCount = 0
    Get-ChildItem -Path "$SourceDir\commands" -Filter "*.md" | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $destCommands -Force
        $cmdCount++
    }
    Log-Ok "$cmdCount commands instalados em $destCommands"
}

function Configure-Mcp {
    param($Name, $Command, $ArgsJson, $EnvJson)

    $settingsFile = "$HOME\.claude\settings.json"
    if (-not (Test-Path $settingsFile)) {
        '{}' | Out-File -FilePath $settingsFile -Encoding utf8
    }

    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json

    if ($settings.mcpServers -and $settings.mcpServers.PSObject.Properties[$Name]) {
        Log-Ok "MCP '$Name' ja configurado"
        return
    }

    if (-not $settings.mcpServers) {
        $settings | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue @{} -Force
    }

    $mcpConfig = @{ type = "stdio"; command = $Command; args = $ArgsJson }
    if ($EnvJson) { $mcpConfig.env = $EnvJson }

    $settings.mcpServers | Add-Member -NotePropertyName $Name -NotePropertyValue $mcpConfig -Force
    $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $settingsFile -Encoding utf8

    Log-Ok "MCP '$Name' configurado"
}

function Setup-GitHubMcp {
    $ghMcp = gh extension list 2>$null | Select-String "github/gh-mcp"
    if (-not $ghMcp) {
        Log-Info "Instalando GitHub MCP..."
        gh extension install github/gh-mcp 2>$null
        if ($LASTEXITCODE -ne 0) {
            Log-Warn "Falha ao instalar gh-mcp. Instale manualmente: gh extension install github/gh-mcp"
            return
        }
    }
    Configure-Mcp -Name "github" -Command "gh" -ArgsJson @("mcp")
}

function Setup-AtlassianMcp {
    $settingsFile = "$HOME\.claude\settings.json"
    if (Test-Path $settingsFile) {
        $content = Get-Content $settingsFile -Raw | ConvertFrom-Json
        if ($content.mcpServers -and $content.mcpServers.PSObject.Properties["mcp-atlassian"]) {
            Log-Ok "MCP Atlassian ja configurado (global)"
            return
        }
    }

    Write-Host ""
    Log-Info "Configurando integracao com Jira/Confluence..."
    Write-Host "  Crie um API token em: https://id.atlassian.com/manage/api-tokens" -ForegroundColor DarkGray
    Write-Host ""

    $email = Prompt-User "Email do Jira:"
    if (-not $email) { Log-Warn "Email nao informado — pulando Atlassian MCP."; return }

    $tokenSecure = Read-Host "  ? API Token do Jira" -AsSecureString
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure))
    if (-not $token) { Log-Warn "Token nao informado — pulando Atlassian MCP."; return }

    $jiraUrl = Prompt-User "URL do Jira (ex: https://your-org.atlassian.net):"
    if (-not $jiraUrl) { $jiraUrl = "https://your-org.atlassian.net" }

    $confluenceUrl = Prompt-User "URL do Confluence (ex: https://your-org.atlassian.net/wiki):"
    if (-not $confluenceUrl) { $confluenceUrl = "$jiraUrl/wiki" }

    # Salvar no .env
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    $envFile = "$InstallDir\.env"
    $envContent = @"
JIRA_URL=$jiraUrl
JIRA_USERNAME=$email
JIRA_API_TOKEN=$token
CONFLUENCE_URL=$confluenceUrl
"@

    if (Test-Path $envFile) {
        $existing = Get-Content $envFile -Raw
        foreach ($line in $envContent -split "`n") {
            $varName = ($line -split "=")[0]
            if ($existing -match "^$varName=") {
                $existing = $existing -replace "(?m)^$varName=.*$", $line
            } else {
                $existing += "`n$line"
            }
        }
        $existing | Out-File -FilePath $envFile -Encoding utf8
    } else {
        $envContent | Out-File -FilePath $envFile -Encoding utf8
    }
    Log-Ok "Credenciais salvas no .env"

    # Detectar runtime: uvx > npx > docker
    $mcpCmd = $null; $mcpArgs = $null
    if (Get-Command uvx -ErrorAction SilentlyContinue) {
        $mcpCmd = "uvx"; $mcpArgs = @("mcp-atlassian")
        Log-Info "Usando uvx para MCP Atlassian"
    } elseif (Get-Command npx -ErrorAction SilentlyContinue) {
        $mcpCmd = "npx"; $mcpArgs = @("mcp-atlassian")
        Log-Info "Usando npx para MCP Atlassian"
    } elseif (Get-Command docker -ErrorAction SilentlyContinue) {
        $mcpCmd = "docker"
        $mcpArgs = @("run","-i","--rm","-e","CONFLUENCE_URL","-e","CONFLUENCE_USERNAME",
                      "-e","CONFLUENCE_API_TOKEN","-e","JIRA_URL","-e","JIRA_USERNAME",
                      "-e","JIRA_API_TOKEN","ghcr.io/sooperset/mcp-atlassian:latest")
        Log-Info "Usando Docker para MCP Atlassian"
    } else {
        Log-Warn "Nenhum runtime encontrado (uvx, npx ou docker). Instale uv: https://docs.astral.sh/uv/"
        return
    }

    $envObj = @{
        JIRA_URL = $jiraUrl; JIRA_USERNAME = $email; JIRA_API_TOKEN = $token
        CONFLUENCE_URL = $confluenceUrl; CONFLUENCE_USERNAME = $email; CONFLUENCE_API_TOKEN = $token
    }

    Configure-Mcp -Name "mcp-atlassian" -Command $mcpCmd -ArgsJson $mcpArgs -EnvJson $envObj
}

function Setup-GeminiKey {
    $envFile = "$InstallDir\.env"
    if ((Test-Path $envFile) -and (Select-String -Path $envFile -Pattern "GEMINI_API_KEY=AIza" -Quiet)) {
        Log-Ok "Gemini API key ja configurada"
        return
    }

    Write-Host ""
    Log-Info "A Gemini API key e usada para embeddings no knowledge-service."
    Write-Host "  Obtenha gratuitamente em: https://aistudio.google.com/apikey" -ForegroundColor DarkGray
    Write-Host ""

    $key = Prompt-User "Gemini API Key (ou Enter para pular):"
    if ($key) {
        if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
        if (Test-Path $envFile) {
            $content = Get-Content $envFile -Raw
            if ($content -match "GEMINI_API_KEY=") {
                $content = $content -replace "GEMINI_API_KEY=.*", "GEMINI_API_KEY=$key"
            } else {
                $content += "`nGEMINI_API_KEY=$key"
            }
            $content | Out-File -FilePath $envFile -Encoding utf8
        } else {
            "GEMINI_API_KEY=$key" | Out-File -FilePath $envFile -Encoding utf8
        }
        Log-Ok "Gemini API key salva"
    } else {
        Log-Warn "Gemini key nao informada — knowledge-service funcionara sem busca semantica."
    }
}

function Setup-KnowledgeService {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Log-Warn "Docker nao encontrado — knowledge-service nao sera iniciado."
        return
    }

    try { $health = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 3 -ErrorAction Stop } catch {}
    if ($health.status -eq "ok") {
        Log-Ok "Knowledge-service ja rodando"
        return
    }

    $start = Prompt-User "Subir knowledge-service agora? (Docker necessario) [S/n]:"
    if ($start -eq "n" -or $start -eq "N") {
        Log-Info "Pulando. Execute depois: cd $InstallDir && docker compose up -d"
        return
    }

    Log-Info "Subindo PostgreSQL + knowledge-service..."
    Push-Location "$SourceDir"
    docker compose -f knowledge-service\docker-compose.yml up -d 2>$null
    Pop-Location

    Start-Sleep -Seconds 5
    try { $health = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 10 -ErrorAction Stop } catch {}
    if ($health.status -eq "ok") {
        Log-Ok "Knowledge-service rodando em http://localhost:8080"
    } else {
        Log-Warn "Knowledge-service nao respondeu. Verifique os logs do Docker."
    }
}

function Save-Version {
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    $Version | Out-File -FilePath "$InstallDir\VERSION" -Encoding utf8
    (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") | Out-File -FilePath "$InstallDir\INSTALLED_AT" -Encoding utf8
}

function Do-Update {
    Write-Host "`nAI Engineer — Atualizacao`n" -ForegroundColor Cyan

    $installedVersion = ""
    if (Test-Path "$InstallDir\VERSION") {
        $installedVersion = (Get-Content "$InstallDir\VERSION" -Raw).Trim()
    }

    try {
        $remoteVersion = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/VERSION" -UseBasicParsing -TimeoutSec 10).Content.Trim()
    } catch {
        Log-Warn "Nao foi possivel verificar atualizacoes."
        return
    }

    if ($installedVersion -eq $remoteVersion) {
        Log-Ok "Voce esta na versao mais recente ($installedVersion)"
        return
    }

    Log-Info "Atualizacao disponivel: $installedVersion → $remoteVersion"
    $confirm = Prompt-User "Atualizar agora? [S/n]:"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        Log-Info "Atualizacao cancelada."
        return
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "ai-engineer-update-$(Get-Random)"
    git clone --depth 1 --branch $RepoBranch $RepoUrl $tmpDir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Log-Err "Falha ao baixar atualizacao."
        return
    }

    $SourceDir = $tmpDir
    Install-SkillsAndCommands

    Copy-Item -Path "$tmpDir\scripts" -Destination $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$tmpDir\knowledge-service" -Destination $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$tmpDir\Makefile" -Destination $InstallDir -Force -ErrorAction SilentlyContinue

    $remoteVersion | Out-File -FilePath "$InstallDir\VERSION" -Encoding utf8
    (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") | Out-File -FilePath "$InstallDir\UPDATED_AT" -Encoding utf8

    Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Log-Ok "Atualizado para versao $remoteVersion"
}

# ══════════════════════════════════════════════════════════════════════════
# MODOS
# ══════════════════════════════════════════════════════════════════════════

if ($Update) {
    Do-Update
    if ($CleanupDir -and (Test-Path $CleanupDir)) { Remove-Item $CleanupDir -Recurse -Force -ErrorAction SilentlyContinue }
    exit 0
}

if ($Skills) {
    Write-Host "`nAI Engineer — Instalacao de Skills`n" -ForegroundColor Cyan
    Install-SkillsAndCommands
    Save-Version
    Write-Host "`nConcluido.`n" -ForegroundColor Green
    if ($CleanupDir -and (Test-Path $CleanupDir)) { Remove-Item $CleanupDir -Recurse -Force -ErrorAction SilentlyContinue }
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════
# MODO COMPLETO
# ══════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║      AI Engineer — Setup v$Version     ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Desenvolvedor autonomo para times de engenharia." -ForegroundColor DarkGray
Write-Host "  Busca tasks do Jira, implementa, testa e abre PRs." -ForegroundColor DarkGray
Write-Host ""

# ── Step 1: Dependencias ─────────────────────────────────────────────────

Log-Step 1 "Verificando dependencias"

$depsOk = $true

foreach ($dep in @(
    @{ Name = "jq";  Hint = "choco install jq" },
    @{ Name = "git"; Hint = "https://git-scm.com/download/win" },
    @{ Name = "gh";  Hint = "choco install gh" }
)) {
    if (Get-Command $dep.Name -ErrorAction SilentlyContinue) {
        Log-Ok "$($dep.Name) encontrado"
    } else {
        Log-Err "$($dep.Name) nao encontrado — $($dep.Hint)"
        $depsOk = $false
    }
}

if ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path "$HOME\.claude")) {
    Log-Ok "Claude Code encontrado"
} else {
    Log-Err "Claude Code nao encontrado — instale em https://claude.ai/code"
    $depsOk = $false
}

if (Get-Command uvx -ErrorAction SilentlyContinue) {
    Log-Ok "uvx encontrado (uv)"
} elseif (Get-Command npx -ErrorAction SilentlyContinue) {
    Log-Ok "npx encontrado (Node.js)"
} else {
    Log-Warn "Nem uvx nem npx encontrados — instale uv (https://docs.astral.sh/uv/) para MCPs"
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Log-Ok "Docker encontrado (para knowledge-service)"
} else {
    Log-Warn "Docker nao encontrado — knowledge-service nao sera iniciado"
}

if (-not $depsOk) {
    Write-Host ""
    Log-Err "Dependencias obrigatorias faltando. Instale e tente novamente."
    exit 1
}

# ── Step 2: Autenticacao ─────────────────────────────────────────────────

Log-Step 2 "Verificando autenticacoes"

$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -eq 0) {
    $ghUser = ($ghStatus | Select-String "Logged in").ToString() -replace '.*account\s+(\S+).*', '$1'
    Log-Ok "GitHub autenticado como $ghUser"
} else {
    Log-Warn "GitHub CLI nao autenticado"
    $doAuth = Prompt-User "Autenticar agora? [S/n]:"
    if ($doAuth -ne "n" -and $doAuth -ne "N") {
        gh auth login
        if ($LASTEXITCODE -ne 0) { Log-Err "Falha na autenticacao do GitHub."; exit 1 }
        Log-Ok "GitHub autenticado"
    } else {
        Log-Err "GitHub CLI e obrigatorio. Execute: gh auth login"
        exit 1
    }
}

# ── Step 3: MCPs ─────────────────────────────────────────────────────────

Log-Step 3 "Configurando integracoes (MCPs)"

if (-not (Test-Path "$HOME\.claude")) { New-Item -ItemType Directory -Path "$HOME\.claude" -Force | Out-Null }
if (-not (Test-Path "$HOME\.claude\settings.json")) { '{}' | Out-File -FilePath "$HOME\.claude\settings.json" -Encoding utf8 }

Setup-GitHubMcp
Setup-AtlassianMcp

# ── Step 4: Skills e Commands ────────────────────────────────────────────

Log-Step 4 "Instalando skills e commands"

Install-SkillsAndCommands

if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
Copy-Item -Path "$SourceDir\scripts" -Destination $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$SourceDir\knowledge-service" -Destination $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$SourceDir\Makefile" -Destination $InstallDir -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$SourceDir\.env.example" -Destination $InstallDir -Force -ErrorAction SilentlyContinue

Log-Ok "Arquivos copiados para $InstallDir"

# ── Step 5: Gemini API Key ───────────────────────────────────────────────

Log-Step 5 "Configurando knowledge-service"

Setup-GeminiKey

# ── Step 6: Knowledge Service ────────────────────────────────────────────

Log-Step 6 "Iniciando knowledge-service"

Setup-KnowledgeService

# ── Step 7: Versao ───────────────────────────────────────────────────────

Log-Step 7 "Finalizando"

Save-Version

# ── Resumo ───────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║         Setup concluido! ✓           ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "  Status:" -ForegroundColor White
Log-Ok "Skills e commands instalados"

$settings = Get-Content "$HOME\.claude\settings.json" -Raw | ConvertFrom-Json
if ($settings.mcpServers -and $settings.mcpServers.PSObject.Properties["github"]) {
    Log-Ok "GitHub MCP configurado"
} else {
    Log-Warn "GitHub MCP nao configurado"
}

if ($settings.mcpServers -and $settings.mcpServers.PSObject.Properties["mcp-atlassian"]) {
    Log-Ok "Atlassian MCP (Jira) configurado"
} else {
    Log-Warn "Atlassian MCP nao configurado"
}

try {
    $health = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 3 -ErrorAction Stop
    if ($health.status -eq "ok") { Log-Ok "Knowledge-service rodando" }
    else { Log-Warn "Knowledge-service nao disponivel" }
} catch {
    Log-Warn "Knowledge-service nao disponivel — execute: cd $InstallDir && docker compose up -d"
}

Write-Host ""
Write-Host "  Proximos passos:" -ForegroundColor White
Write-Host ""
Write-Host "  1. Abra o terminal na raiz dos seus repos:" -ForegroundColor Cyan
Write-Host "     cd ~\git" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2. Abra o Claude Code:" -ForegroundColor Cyan
Write-Host "     claude" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3. Teste com dry-run:" -ForegroundColor Cyan
Write-Host "     /engineer --dry-run" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  4. Execute de verdade:" -ForegroundColor Cyan
Write-Host "     /engineer" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Versao: $Version | Atualizar: .\install.ps1 -Update" -ForegroundColor DarkGray
Write-Host "  Docs: https://github.com/wallacehenriquesilva/ai-engineer" -ForegroundColor DarkGray
Write-Host ""

# ── Cleanup ───────────────────────────────────────────────────────────────

if ($CleanupDir -and (Test-Path $CleanupDir)) {
    Remove-Item -Path $CleanupDir -Recurse -Force -ErrorAction SilentlyContinue
}
