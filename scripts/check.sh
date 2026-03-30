#!/bin/bash
# check.sh — Valida que o ambiente está pronto para usar o AI Engineer
# Uso: make check

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

OK=0
WARN=0
FAIL=0

check_ok()   { OK=$((OK + 1));   echo -e "  ${GREEN}✓${NC} $1"; }
check_warn() { WARN=$((WARN + 1)); echo -e "  ${YELLOW}!${NC} $1"; }
check_fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}✗${NC} $1"; }

echo ""
echo -e "${BOLD}${CYAN}AI Engineer — Diagnóstico do Ambiente${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"

# ── 1. Dependências ──────────────────────────────────────────────────────────

echo -e "\n${BOLD}Dependências${NC}"

for cmd in jq git curl; do
  command -v "$cmd" >/dev/null 2>&1 && check_ok "$cmd" || check_fail "$cmd não encontrado"
done

if command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ]; then
  check_ok "Claude Code"
else
  check_fail "Claude Code não encontrado — https://claude.ai/code"
fi

if command -v gh >/dev/null 2>&1; then
  check_ok "GitHub CLI (gh)"
else
  check_fail "GitHub CLI não encontrado — brew install gh"
fi

if command -v uvx >/dev/null 2>&1; then
  check_ok "uvx (uv)"
elif command -v npx >/dev/null 2>&1; then
  check_ok "npx (Node.js)"
else
  check_warn "Nem uvx nem npx — MCP do Atlassian pode não funcionar"
fi

if command -v docker >/dev/null 2>&1; then
  check_ok "Docker"
else
  check_warn "Docker não encontrado — knowledge-service indisponível"
fi

# ── 2. Autenticação ─────────────────────────────────────────────────────────

echo -e "\n${BOLD}Autenticação${NC}"

if gh auth status >/dev/null 2>&1; then
  GH_USER=$(gh auth status 2>&1 | grep "Logged in" | head -1 | awk '{print $7}')
  check_ok "GitHub autenticado ($GH_USER)"
else
  check_fail "GitHub CLI não autenticado — execute: gh auth login"
fi

# ── 3. MCPs ──────────────────────────────────────────────────────────────────

echo -e "\n${BOLD}MCPs (integrações)${NC}"

SETTINGS="$HOME/.claude/settings.json"
MCP_JSON=".mcp.json"

# GitHub MCP
if ([ -f "$SETTINGS" ] && jq -e '.mcpServers.github' "$SETTINGS" >/dev/null 2>&1) || \
   ([ -f "$MCP_JSON" ] && jq -e '.mcpServers.github' "$MCP_JSON" >/dev/null 2>&1); then
  check_ok "GitHub MCP"
else
  check_fail "GitHub MCP não configurado — execute: ./install.sh"
fi

# Atlassian MCP
if ([ -f "$SETTINGS" ] && jq -e '.mcpServers."mcp-atlassian"' "$SETTINGS" >/dev/null 2>&1) || \
   ([ -f "$MCP_JSON" ] && jq -e '.mcpServers."mcp-atlassian"' "$MCP_JSON" >/dev/null 2>&1); then
  check_ok "Atlassian MCP (Jira)"
else
  check_fail "Atlassian MCP não configurado — execute: ./install.sh"
fi

# ── 4. Skills e Commands ────────────────────────────────────────────────────

echo -e "\n${BOLD}Skills e Commands${NC}"

SKILLS_DIR="$HOME/.claude/skills"
COMMANDS_DIR="$HOME/.claude/commands"

if [ -d "$SKILLS_DIR" ]; then
  SKILL_COUNT=$(find "$SKILLS_DIR" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$SKILL_COUNT" -gt 0 ]; then
    check_ok "$SKILL_COUNT skills instaladas"
  else
    check_fail "Nenhuma skill encontrada em $SKILLS_DIR"
  fi
else
  check_fail "Diretório de skills não existe — execute: make install-skills"
fi

if [ -d "$COMMANDS_DIR" ]; then
  CMD_COUNT=$(find "$COMMANDS_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$CMD_COUNT" -gt 0 ]; then
    check_ok "$CMD_COUNT commands instalados"
  else
    check_fail "Nenhum command encontrado em $COMMANDS_DIR"
  fi
else
  check_fail "Diretório de commands não existe — execute: make install-skills"
fi

# ── 5. Knowledge Service ────────────────────────────────────────────────────

echo -e "\n${BOLD}Knowledge Service${NC}"

if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then
  check_ok "Knowledge-service rodando"

  # Verificar repos indexados
  REPO_COUNT=$(curl -sf "http://localhost:8080/repos" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
  if [ "$REPO_COUNT" -gt 0 ]; then
    check_ok "$REPO_COUNT repos indexados"
  else
    check_warn "Nenhum repo indexado — execute: make scan"
  fi
else
  check_warn "Knowledge-service não disponível — execute: make up"
  check_warn "Sem knowledge-service: busca semântica e aprendizados compartilhados ficam indisponíveis"
  check_warn "O agente funciona normalmente, apenas sem esses recursos"
fi

# ── 6. Versão ────────────────────────────────────────────────────────────────

echo -e "\n${BOLD}Versão${NC}"

if [ -f "$HOME/.ai-engineer/VERSION" ]; then
  VERSION=$(cat "$HOME/.ai-engineer/VERSION" | tr -d '[:space:]')
  check_ok "Versão instalada: $VERSION"
else
  check_warn "Versão não registrada — execute: ./install.sh"
fi

if [ -f "VERSION" ]; then
  REPO_VERSION=$(cat VERSION | tr -d '[:space:]')
  INSTALLED_VERSION=$(cat "$HOME/.ai-engineer/VERSION" 2>/dev/null | tr -d '[:space:]')
  if [ "$REPO_VERSION" != "$INSTALLED_VERSION" ] && [ -n "$INSTALLED_VERSION" ]; then
    check_warn "Versão instalada ($INSTALLED_VERSION) difere do repo ($REPO_VERSION) — execute: make update"
  fi
fi

# ── Resultado ────────────────────────────────────────────────────────────────

TOTAL=$((OK + WARN + FAIL))
echo ""
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "  ${GREEN}✓ $OK${NC}  ${YELLOW}! $WARN${NC}  ${RED}✗ $FAIL${NC}  (total: $TOTAL)"
echo ""

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}Ambiente pronto!${NC} Execute: claude → /engineer --dry-run"
elif [ "$FAIL" -eq 0 ]; then
  echo -e "  ${YELLOW}${BOLD}Ambiente funcional com ressalvas.${NC} O agente funciona, mas alguns recursos estão indisponíveis."
else
  echo -e "  ${RED}${BOLD}Ambiente com problemas.${NC} Corrija os itens com ✗ antes de usar."
fi

echo ""
exit $FAIL
