#!/bin/bash
# install.sh — Setup completo do AI Engineer
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/install.sh -o install.sh && bash install.sh
#   ./install.sh              # interativo completo
#   ./install.sh --skills     # apenas instala skills/commands (sem onboarding)
#   ./install.sh --update     # atualiza para a versão mais recente

set -eo pipefail

VERSION="0.1.0"
REPO_URL="${CA_AI_ENGINEER_REPO:-https://github.com/wallacehenriquesilva/ai-engineer.git}"
REPO_BRANCH="${CA_AI_ENGINEER_BRANCH:-main}"
INSTALL_DIR="${CA_AI_ENGINEER_DIR:-$HOME/.ai-engineer}"
CLEANUP_TMPDIR=""

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
log_err()   { echo -e "  ${RED}✗${NC} $1"; }
log_info()  { echo -e "  ${CYAN}→${NC} $1"; }
log_step()  { echo -e "\n${BOLD}${CYAN}[$1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"; }
prompt()    { echo -en "  ${CYAN}?${NC} $1 "; }

TOTAL_STEPS=7
MODE="full"
[ "${1:-}" = "--skills" ] && MODE="skills"
[ "${1:-}" = "--update" ] && MODE="update"

# ── Resolve source ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

if [ -d "$SCRIPT_DIR/skills" ] && [ -d "$SCRIPT_DIR/commands" ]; then
  SOURCE_DIR="$SCRIPT_DIR"
else
  TMPDIR="$(mktemp -d)"
  CLEANUP_TMPDIR="$TMPDIR"
  echo -e "${CYAN}Baixando AI Engineer...${NC}"
  if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMPDIR" 2>/dev/null; then
    log_err "Falha ao clonar $REPO_URL"
    rm -rf "$TMPDIR"
    exit 1
  fi
  SOURCE_DIR="$TMPDIR"
fi

cleanup() { [ -n "$CLEANUP_TMPDIR" ] && rm -rf "$CLEANUP_TMPDIR"; }
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════════
# FUNÇÕES
# ══════════════════════════════════════════════════════════════════════════════

check_dependency() {
  local name="$1" install_hint="$2"
  if command -v "$name" >/dev/null 2>&1; then
    log_ok "$name encontrado"
    return 0
  else
    log_err "$name não encontrado — $install_hint"
    return 1
  fi
}

install_skills_and_commands() {
  local dest_skills="$HOME/.claude/skills"
  local dest_commands="$HOME/.claude/commands"
  local count=0

  mkdir -p "$dest_skills" "$dest_commands"

  for skill in "$SOURCE_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    local name=$(basename "$skill")
    mkdir -p "$dest_skills/$name"
    cp -R "$skill"/* "$dest_skills/$name/" 2>/dev/null
    count=$((count + 1))
  done
  log_ok "$count skills instaladas em $dest_skills"

  local cmd_count=0
  for cmd in "$SOURCE_DIR"/commands/*.md; do
    [ -f "$cmd" ] || continue
    cp "$cmd" "$dest_commands/"
    cmd_count=$((cmd_count + 1))
  done
  log_ok "$cmd_count commands instalados em $dest_commands"
}

configure_mcp() {
  local name="$1" type="$2" command="$3" args="$4" env_json="$5"
  local settings_file="$HOME/.claude/settings.json"

  # Cria settings.json se não existir
  if [ ! -f "$settings_file" ]; then
    echo '{}' > "$settings_file"
  fi

  # Verifica se o MCP já está configurado
  if jq -e ".mcpServers.\"$name\"" "$settings_file" >/dev/null 2>&1; then
    log_ok "MCP '$name' já configurado"
    return 0
  fi

  # Adiciona o MCP
  local tmp=$(mktemp)
  if [ -n "$env_json" ]; then
    jq --arg name "$name" --arg type "$type" --arg cmd "$command" \
       --argjson args "$args" --argjson env "$env_json" \
       '.mcpServers[$name] = {type: $type, command: $cmd, args: $args, env: $env}' \
       "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
  else
    jq --arg name "$name" --arg type "$type" --arg cmd "$command" \
       --argjson args "$args" \
       '.mcpServers[$name] = {type: $type, command: $cmd, args: $args}' \
       "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
  fi

  log_ok "MCP '$name' configurado"
}

setup_github_mcp() {
  # GitHub MCP via gh CLI extension (shuymn/gh-mcp wraps github/github-mcp-server)
  if ! gh extension list 2>/dev/null | grep -q "gh-mcp"; then
    log_info "Instalando GitHub MCP..."
    gh extension install shuymn/gh-mcp 2>/dev/null || {
      log_warn "Falha ao instalar gh-mcp. Instale manualmente: gh extension install shuymn/gh-mcp"
      return 1
    }
  fi

  configure_mcp "github" "stdio" "gh" '["mcp"]' ""
}

setup_atlassian_mcp() {
  local email="" token="" jira_url="" confluence_url=""

  # Verifica se já está configurado
  if jq -e '.mcpServers."mcp-atlassian"' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    log_ok "MCP Atlassian já configurado (global)"
    return 0
  fi

  echo ""
  log_info "Configurando integração com Jira/Confluence..."
  echo -e "  ${DIM}Crie um API token em: https://id.atlassian.com/manage/api-tokens${NC}"
  echo ""

  prompt "Email do Jira:"
  read -r email
  [ -z "$email" ] && { log_warn "Email não informado — pulando Atlassian MCP."; return 1; }

  prompt "API Token do Jira:"
  read -rs token
  echo ""
  [ -z "$token" ] && { log_warn "Token não informado — pulando Atlassian MCP."; return 1; }

  prompt "URL do Jira (ex: https://your-org.atlassian.net):"
  read -r jira_url
  [ -z "$jira_url" ] && jira_url="https://your-org.atlassian.net"

  confluence_url="${jira_url}/wiki"
  log_ok "Confluence URL: $confluence_url"

  # Salvar credenciais no .env para o .mcp.json usar
  local env_file="$INSTALL_DIR/.env"
  mkdir -p "$INSTALL_DIR"
  if [ -f "$env_file" ]; then
    # Atualiza ou adiciona cada variável
    for var_pair in "JIRA_URL=$jira_url" "JIRA_USERNAME=$email" "JIRA_API_TOKEN=$token" "CONFLUENCE_URL=$confluence_url"; do
      local var_name="${var_pair%%=*}"
      if grep -q "^$var_name=" "$env_file" 2>/dev/null; then
        sed -i.bak "s|^$var_name=.*|$var_pair|" "$env_file"
      else
        echo "$var_pair" >> "$env_file"
      fi
    done
    rm -f "$env_file.bak"
  fi
  log_ok "Credenciais salvas no .env"

  # Registrar no settings.json global (funciona de qualquer diretório)
  # mcp-atlassian é um pacote Python (PyPI) — só funciona com uvx ou docker
  local mcp_cmd="" mcp_args=""
  if command -v uvx >/dev/null 2>&1; then
    mcp_cmd="uvx"
    mcp_args='["mcp-atlassian"]'
    log_info "Usando uvx para MCP Atlassian"
  elif command -v docker >/dev/null 2>&1; then
    mcp_cmd="docker"
    mcp_args='["run","-i","--rm","-e","CONFLUENCE_URL","-e","CONFLUENCE_USERNAME","-e","CONFLUENCE_API_TOKEN","-e","JIRA_URL","-e","JIRA_USERNAME","-e","JIRA_API_TOKEN","ghcr.io/sooperset/mcp-atlassian:latest"]'
    log_info "Usando Docker para MCP Atlassian"
  else
    log_info "uvx não encontrado — instalando uv..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null; then
      export PATH="$HOME/.local/bin:$PATH"
      if command -v uvx >/dev/null 2>&1; then
        mcp_cmd="uvx"
        mcp_args='["mcp-atlassian"]'
        log_ok "uv instalado — usando uvx para MCP Atlassian"
      else
        log_warn "uv instalado mas uvx não encontrado no PATH. Reinicie o terminal e execute novamente."
        return 1
      fi
    else
      log_warn "Falha ao instalar uv. Instale manualmente: curl -LsSf https://astral.sh/uv/install.sh | sh"
      return 1
    fi
  fi

  local env_json
  env_json=$(jq -n \
    --arg email "$email" \
    --arg token "$token" \
    --arg jira_url "$jira_url" \
    --arg confluence_url "$confluence_url" \
    '{JIRA_URL: $jira_url, JIRA_USERNAME: $email, JIRA_API_TOKEN: $token,
      CONFLUENCE_URL: $confluence_url, CONFLUENCE_USERNAME: $email, CONFLUENCE_API_TOKEN: $token}')

  configure_mcp "mcp-atlassian" "stdio" "$mcp_cmd" "$mcp_args" "$env_json"
}

setup_gemini_key() {
  local env_file="$INSTALL_DIR/.env"

  if [ -f "$env_file" ] && grep -q "GEMINI_API_KEY=AIza" "$env_file" 2>/dev/null; then
    log_ok "Gemini API key já configurada"
    return 0
  fi

  echo ""
  log_info "A Gemini API key é usada para embeddings no knowledge-service."
  echo -e "  ${DIM}Obtenha gratuitamente em: https://aistudio.google.com/apikey${NC}"
  echo ""

  prompt "Gemini API Key (ou Enter para pular):"
  read -rs gemini_key
  echo ""

  if [ -n "$gemini_key" ]; then
    mkdir -p "$INSTALL_DIR"
    if [ -f "$env_file" ]; then
      # Atualiza key existente
      if grep -q "GEMINI_API_KEY" "$env_file"; then
        sed -i.bak "s|GEMINI_API_KEY=.*|GEMINI_API_KEY=$gemini_key|" "$env_file"
        rm -f "$env_file.bak"
      else
        echo "GEMINI_API_KEY=$gemini_key" >> "$env_file"
      fi
    else
      cp "$SOURCE_DIR/.env.example" "$env_file"
      sed -i.bak "s|GEMINI_API_KEY=.*|GEMINI_API_KEY=$gemini_key|" "$env_file"
      rm -f "$env_file.bak"
    fi
    log_ok "Gemini API key salva"
  else
    log_warn "Gemini key não informada — knowledge-service funcionará sem busca semântica."
  fi
}

setup_knowledge_service() {
  if ! command -v docker >/dev/null 2>&1; then
    log_warn "Docker não encontrado — knowledge-service não será iniciado."
    log_warn "Instale Docker e execute: cd $INSTALL_DIR && make up"
    return 1
  fi

  if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
    log_ok "Knowledge-service já rodando"
    return 0
  fi

  prompt "Subir knowledge-service agora? (Docker necessário) [S/n]:"
  read -r start_ks
  if [ "$start_ks" = "n" ] || [ "$start_ks" = "N" ]; then
    log_info "Pulando. Execute depois: cd $INSTALL_DIR && make up"
    return 0
  fi

  log_info "Subindo PostgreSQL + knowledge-service..."
  (cd "$SOURCE_DIR" && docker compose -f knowledge-service/docker-compose.yml up -d 2>/dev/null) || {
    log_warn "Falha ao subir o knowledge-service. Execute manualmente: make up"
    return 1
  }

  # Aguarda ficar disponível
  for i in $(seq 1 15); do
    curl -sf "http://localhost:8080/health" >/dev/null 2>&1 && break
    sleep 2
  done

  if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
    log_ok "Knowledge-service rodando em http://localhost:8080"
  else
    log_warn "Knowledge-service não respondeu em 30s. Verifique: docker logs knowledge-service-knowledge-service-1"
  fi
}

save_version() {
  mkdir -p "$INSTALL_DIR"
  echo "$VERSION" > "$INSTALL_DIR/VERSION"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$INSTALL_DIR/INSTALLED_AT"
}

check_for_updates() {
  local current_version installed_version=""

  if [ -f "$INSTALL_DIR/VERSION" ]; then
    installed_version=$(cat "$INSTALL_DIR/VERSION")
  fi

  # Busca versão remota
  local remote_version
  remote_version=$(curl -sf "https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/VERSION" 2>/dev/null || echo "")

  if [ -z "$remote_version" ]; then
    log_warn "Não foi possível verificar atualizações."
    return 1
  fi

  if [ "$installed_version" = "$remote_version" ]; then
    log_ok "Você está na versão mais recente ($installed_version)"
    return 0
  else
    log_info "Atualização disponível: $installed_version → $remote_version"
    return 2
  fi
}

do_update() {
  echo -e "\n${BOLD}${CYAN}AI Engineer — Atualização${NC}\n"

  check_for_updates
  local status=$?

  if [ $status -eq 0 ]; then
    return 0
  fi

  prompt "Atualizar agora? [S/n]:"
  read -r do_up
  if [ "$do_up" = "n" ] || [ "$do_up" = "N" ]; then
    log_info "Atualização cancelada."
    return 0
  fi

  # Re-clone e reinstala
  log_info "Baixando versão mais recente..."
  local tmpdir
  tmpdir=$(mktemp -d)
  if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$tmpdir" 2>/dev/null; then
    log_err "Falha ao baixar atualização."
    rm -rf "$tmpdir"
    return 1
  fi

  # Copia novos arquivos
  SOURCE_DIR="$tmpdir"
  install_skills_and_commands

  # Atualiza scripts e templates
  cp -R "$tmpdir/scripts" "$INSTALL_DIR/" 2>/dev/null
  cp -R "$tmpdir/knowledge-service" "$INSTALL_DIR/" 2>/dev/null
  cp -R "$tmpdir/docs" "$INSTALL_DIR/" 2>/dev/null
  cp "$tmpdir/Makefile" "$INSTALL_DIR/" 2>/dev/null

  # Atualiza versão
  local new_version
  new_version=$(cat "$tmpdir/VERSION" 2>/dev/null || echo "$VERSION")
  echo "$new_version" > "$INSTALL_DIR/VERSION"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$INSTALL_DIR/UPDATED_AT"

  rm -rf "$tmpdir"
  log_ok "Atualizado para versão $new_version"

  # Rebuild knowledge-service se Docker estiver disponível
  if command -v docker >/dev/null 2>&1 && curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
    prompt "Rebuildar knowledge-service? [S/n]:"
    read -r rebuild
    if [ "$rebuild" != "n" ] && [ "$rebuild" != "N" ]; then
      (cd "$INSTALL_DIR" && docker compose -f knowledge-service/docker-compose.yml build knowledge-service --no-cache 2>/dev/null && \
       docker compose -f knowledge-service/docker-compose.yml up -d knowledge-service 2>/dev/null)
      log_ok "Knowledge-service atualizado"
    fi
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MODO: --update
# ══════════════════════════════════════════════════════════════════════════════

if [ "$MODE" = "update" ]; then
  do_update
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# MODO: --skills (apenas skills, sem onboarding)
# ══════════════════════════════════════════════════════════════════════════════

if [ "$MODE" = "skills" ]; then
  echo -e "\n${BOLD}${CYAN}AI Engineer — Instalação de Skills${NC}\n"
  install_skills_and_commands
  save_version
  echo -e "\n${GREEN}Concluído.${NC}\n"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# MODO: full (onboarding completo)
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║      AI Engineer — Setup v$VERSION      ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "${DIM}  Desenvolvedor autônomo para times de engenharia.${NC}"
echo -e "${DIM}  Busca tasks do Jira, implementa, testa e abre PRs.${NC}"
echo ""

# ── Step 1: Dependências ─────────────────────────────────────────────────────

log_step 1 "Verificando dependências"

DEPS_OK=true
check_dependency "jq"     "brew install jq"           || DEPS_OK=false
check_dependency "git"    "brew install git"           || DEPS_OK=false
check_dependency "curl"   "brew install curl"          || DEPS_OK=false

# Claude Code — obrigatório
if command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ]; then
  log_ok "Claude Code encontrado"
else
  log_err "Claude Code não encontrado — instale em https://claude.ai/code"
  DEPS_OK=false
fi

# gh CLI — obrigatório
check_dependency "gh" "brew install gh" || DEPS_OK=false

# uvx ou npx — para MCPs
if command -v uvx >/dev/null 2>&1; then
  log_ok "uvx encontrado (uv)"
elif command -v npx >/dev/null 2>&1; then
  log_ok "npx encontrado (Node.js)"
else
  log_warn "Nem uvx nem npx encontrados — instale uv (https://docs.astral.sh/uv/) para MCPs"
fi

# Docker — opcional (apenas para knowledge-service)
if command -v docker >/dev/null 2>&1; then
  log_ok "Docker encontrado (para knowledge-service)"
else
  log_warn "Docker não encontrado — knowledge-service não será iniciado"
  log_warn "Instale em https://docker.com (opcional, para busca semântica)"
fi

if [ "$DEPS_OK" = false ]; then
  echo ""
  log_err "Dependências obrigatórias faltando. Instale e tente novamente."
  exit 1
fi

# ── Step 2: Autenticação ─────────────────────────────────────────────────────

log_step 2 "Verificando autenticações"

# GitHub
if gh auth status >/dev/null 2>&1; then
  GH_USER=$(gh auth status 2>&1 | grep "Logged in" | awk '{print $7}')
  log_ok "GitHub autenticado como $GH_USER"
else
  log_warn "GitHub CLI não autenticado"
  prompt "Autenticar agora? [S/n]:"
  read -r do_gh_auth
  if [ "$do_gh_auth" != "n" ] && [ "$do_gh_auth" != "N" ]; then
    gh auth login || { log_err "Falha na autenticação do GitHub."; exit 1; }
    log_ok "GitHub autenticado"
  else
    log_err "GitHub CLI é obrigatório. Execute: gh auth login"
    exit 1
  fi
fi

# ── Step 3: MCPs ─────────────────────────────────────────────────────────────

log_step 3 "Configurando integrações (MCPs)"

mkdir -p "$HOME/.claude"
[ ! -f "$HOME/.claude/settings.json" ] && echo '{}' > "$HOME/.claude/settings.json"

# GitHub MCP
setup_github_mcp

# Atlassian MCP (Jira + Confluence)
setup_atlassian_mcp || true

# ── Step 4: Skills e Commands ────────────────────────────────────────────────

log_step 4 "Instalando skills e commands"

install_skills_and_commands

# Copia scripts, configs e templates para INSTALL_DIR
mkdir -p "$INSTALL_DIR"
cp -R "$SOURCE_DIR/scripts"           "$INSTALL_DIR/" 2>/dev/null || true
cp -R "$SOURCE_DIR/knowledge-service" "$INSTALL_DIR/" 2>/dev/null || true
cp -R "$SOURCE_DIR/docs"              "$INSTALL_DIR/" 2>/dev/null || true
cp    "$SOURCE_DIR/Makefile"          "$INSTALL_DIR/" 2>/dev/null || true
cp    "$SOURCE_DIR/.env.example"      "$INSTALL_DIR/" 2>/dev/null || true

log_ok "Arquivos copiados para $INSTALL_DIR"

# ── Step 5: Gemini API Key ───────────────────────────────────────────────────

log_step 5 "Configurando knowledge-service"

setup_gemini_key

# ── Step 6: Knowledge Service ────────────────────────────────────────────────

log_step 6 "Iniciando knowledge-service"

setup_knowledge_service || true

# ── Step 7: Versão ───────────────────────────────────────────────────────────

log_step 7 "Finalizando"

save_version

# ── Resumo ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║         Setup concluído! ✓           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# Status de cada componente
echo -e "${BOLD}  Status:${NC}"
log_ok "Skills e commands instalados"

if jq -e '.mcpServers.github' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  log_ok "GitHub MCP configurado"
else
  log_warn "GitHub MCP não configurado"
fi

if jq -e '.mcpServers."mcp-atlassian"' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  log_ok "Atlassian MCP (Jira) configurado"
else
  log_warn "Atlassian MCP não configurado — execute novamente o instalador para configurar"
fi

if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
  log_ok "Knowledge-service rodando"
else
  log_warn "Knowledge-service não disponível — execute: cd $INSTALL_DIR && make up"
fi

echo ""
echo -e "${BOLD}  Próximos passos:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Abra o terminal na raiz dos seus repos:"
echo -e "     ${DIM}cd ~/git${NC}"
echo ""
echo -e "  ${CYAN}2.${NC} Abra o Claude Code:"
echo -e "     ${DIM}claude${NC}"
echo ""
echo -e "  ${CYAN}3.${NC} Teste com dry-run:"
echo -e "     ${DIM}/engineer --dry-run${NC}"
echo ""
echo -e "  ${CYAN}4.${NC} Execute de verdade:"
echo -e "     ${DIM}/engineer${NC}"
echo ""
echo -e "${DIM}  Versão: $VERSION | Atualizar: ./install.sh --update${NC}"
echo -e "${DIM}  Docs: https://github.com/wallacehenriquesilva/ai-engineer${NC}"
echo ""
