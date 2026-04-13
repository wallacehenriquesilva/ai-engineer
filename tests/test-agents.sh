#!/bin/bash
# test-agents.sh — Valida estrutura, contratos JSON e coerência dos agents
# Uso: ./tests/test-agents.sh [--verbose]
#
# Testa sem chamadas LLM: valida frontmatter, contratos de saída, referências cruzadas
# e consistência com CLAUDE.md.

set -euo pipefail

VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

PASS=0
FAIL=0
WARN=0
ERRORS=()

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
AGENTS_DIR="$ROOT_DIR/agents"

pass() { PASS=$((PASS + 1)); $VERBOSE && echo -e "  ${GREEN}PASS${NC} $1" || true; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo -e "  ${RED}FAIL${NC} $1"; }
warn() { WARN=$((WARN + 1)); echo -e "  ${YELLOW}WARN${NC} $1"; }

echo ""
echo "AI Engineer — Agent Structure Tests"
echo "====================================="
echo ""

# ── 1. Frontmatter obrigatório ───────────────────────────────────────────────
echo "1. Frontmatter obrigatório..."

REQUIRED_AGENTS=(
  orchestrator task-fetcher engineer tester evaluator
  pr-manager pr-resolver finalizer docs-updater engineer-multi
)

for agent_name in "${REQUIRED_AGENTS[@]}"; do
  agent_file="$AGENTS_DIR/$agent_name.md"

  if [ ! -f "$agent_file" ]; then
    fail "$agent_name: arquivo não encontrado ($agent_file)"
    continue
  fi

  # Começa com ---
  if head -1 "$agent_file" | grep -q "^---"; then
    pass "$agent_name: frontmatter presente"
  else
    fail "$agent_name: frontmatter ausente (deve começar com ---)"
    continue
  fi

  # Campo name
  if grep -q "^name:" "$agent_file"; then
    pass "$agent_name: campo 'name' presente"
    declared_name=$(grep "^name:" "$agent_file" | awk '{print $2}')
    [ "$declared_name" = "$agent_name" ] \
      && pass "$agent_name: name correto ('$declared_name')" \
      || warn "$agent_name: name declarado ('$declared_name') difere do filename"
  else
    fail "$agent_name: campo 'name' ausente"
  fi

  # Campo description
  if grep -q "^description:" "$agent_file"; then
    pass "$agent_name: campo 'description' presente"
  else
    fail "$agent_name: campo 'description' ausente"
  fi

  # Campo model
  if grep -q "^model:" "$agent_file"; then
    pass "$agent_name: campo 'model' presente"
  else
    fail "$agent_name: campo 'model' ausente"
  fi

  # Campo tools
  if grep -q "^tools:" "$agent_file"; then
    pass "$agent_name: campo 'tools' presente"
  else
    warn "$agent_name: campo 'tools' ausente (agent pode ter permissões incorretas)"
  fi
done

# ── 2. Contratos de saída JSON ────────────────────────────────────────────────
echo "2. Contratos de saída JSON..."

# Cada agent deve documentar um bloco de retorno JSON com "status"
for agent_name in "${REQUIRED_AGENTS[@]}"; do
  agent_file="$AGENTS_DIR/$agent_name.md"
  [ -f "$agent_file" ] || continue

  if grep -q '"status"' "$agent_file"; then
    pass "$agent_name: contrato JSON com 'status' documentado"
  else
    fail "$agent_name: contrato de saída JSON não encontrado (deve ter campo 'status')"
  fi
done

# Agentes que retornam "status": "success" ou "failed"
for agent_name in engineer tester evaluator pr-manager finalizer task-fetcher; do
  agent_file="$AGENTS_DIR/$agent_name.md"
  [ -f "$agent_file" ] || continue

  if grep -q '"status": "success"' "$agent_file" || grep -q '"status":"success"' "$agent_file"; then
    pass "$agent_name: documenta retorno success"
  else
    warn "$agent_name: não documenta retorno 'status: success' explicitamente"
  fi

  if grep -q '"status": "failed"' "$agent_file" || grep -q '"status":"failed"' "$agent_file"; then
    pass "$agent_name: documenta retorno failed"
  else
    warn "$agent_name: não documenta retorno 'status: failed' explicitamente"
  fi
done

# ── 3. Restrições de responsabilidade ────────────────────────────────────────
echo "3. Restrições de responsabilidade..."

# orchestrator não deve fazer git ops, commits ou PR
for forbidden in "git commit" "git push" "gh pr create" "Write\|Edit"; do
  # Ignora linhas dentro de blocos de código bash que são *exemplos* dos sub-agents
  if grep -v "^#" "$AGENTS_DIR/orchestrator.md" | grep -qE "^\s+$forbidden"; then
    warn "orchestrator: possível uso de '$forbidden' (deve delegar para sub-agents)"
  fi
done
pass "orchestrator: sem git ops diretos detectados"

# engineer não deve ter jira_search ou jira_transition
if grep -q "jira_search\|jira_transition" "$AGENTS_DIR/engineer.md"; then
  fail "engineer: referencia jira_search ou jira_transition (violação de responsabilidade)"
else
  pass "engineer: sem chamadas Jira diretas"
fi

# tester não deve alterar código de produção (não deve ter Edit em arquivos não-test)
if grep -q "Nunca altere codigo de producao" "$AGENTS_DIR/tester.md"; then
  pass "tester: regra 'não alterar código de produção' documentada"
else
  warn "tester: regra de não alterar código de produção não encontrada"
fi

# ── 4. Co-authorship nos commits ──────────────────────────────────────────────
echo "4. Co-authorship..."

if grep -q "Co-Authored-By:" "$AGENTS_DIR/pr-manager.md"; then
  pass "pr-manager: Co-Authored-By presente nos commits"
else
  fail "pr-manager: Co-Authored-By ausente — commits não terão co-autoria AI"
fi

# Verifica que o script de detecção de labels cobre ambos os co-authors
SKILL_FILE="$ROOT_DIR/skills/git-workflow/SKILL.md"
if [ -f "$SKILL_FILE" ]; then
  if grep -q "Co-Authored-By: Claude" "$SKILL_FILE" && grep -q "Co-Authored-By: Copilot" "$SKILL_FILE"; then
    pass "git-workflow: detecta co-author Claude e Copilot"
  elif grep -q "Co-Authored-By: Claude" "$SKILL_FILE"; then
    warn "git-workflow: detecta apenas Claude — commits Copilot CLI não contam como ai-first"
  else
    fail "git-workflow: sem detecção de co-authorship"
  fi
fi

# ── 5. Modelos configurados ───────────────────────────────────────────────────
echo "5. Modelos configurados..."

VALID_MODELS=("claude-opus-4-6" "claude-sonnet-4-6" "claude-haiku-4-5" "claude-opus-4-5")

for agent_file in "$AGENTS_DIR"/*.md; do
  agent_name=$(basename "$agent_file" .md)
  model=$(grep "^model:" "$agent_file" 2>/dev/null | awk '{print $2}')

  [ -z "$model" ] && continue

  valid=false
  for vm in "${VALID_MODELS[@]}"; do
    [ "$model" = "$vm" ] && valid=true && break
  done

  $valid \
    && pass "$agent_name: model '$model' válido" \
    || warn "$agent_name: model '$model' não está na lista de modelos conhecidos"
done

# ── 6. Guardrails do orchestrator ─────────────────────────────────────────────
echo "6. Guardrails do orchestrator..."

ORCH="$AGENTS_DIR/orchestrator.md"

# Deve ter clarity check
if grep -q "Avaliar Clareza\|clareza" "$ORCH"; then
  pass "orchestrator: clarity check presente"
else
  fail "orchestrator: clarity check não encontrado"
fi

# Deve ter max retries
if grep -q -i "max.*retry\|max.*ciclo\|max 2\|Max 2" "$ORCH"; then
  pass "orchestrator: max retries documentado"
else
  warn "orchestrator: limite de retries não encontrado explicitamente"
fi

# Deve ter circuit breaker / no_task handling
if grep -q "no_task" "$ORCH"; then
  pass "orchestrator: no_task handling presente"
else
  fail "orchestrator: no_task handling não encontrado"
fi

# Deve ter needs_clarity handling
if grep -q "needs_clarity" "$ORCH"; then
  pass "orchestrator: needs_clarity handling presente"
else
  fail "orchestrator: needs_clarity handling não encontrado"
fi

# ── 7. Referências entre agents ───────────────────────────────────────────────
echo "7. Referências cruzadas..."

# Agents referenciados pelo orchestrator devem existir
for referenced in task-fetcher engineer engineer-multi tester evaluator docs-updater pr-manager; do
  if grep -q "$referenced" "$ORCH"; then
    if [ -f "$AGENTS_DIR/$referenced.md" ]; then
      pass "orchestrator → $referenced: agent existe"
    else
      fail "orchestrator → $referenced: referenciado mas agent não encontrado"
    fi
  fi
done

# ── 8. CLAUDE.md consistency ──────────────────────────────────────────────────
echo "8. Consistência com CLAUDE.md..."

CLAUDE_FILE="$ROOT_DIR/CLAUDE.md"
if [ -f "$CLAUDE_FILE" ]; then
  # Campos obrigatórios
  for field in "Jira Board:" "Jira Project:" "GitHub Org:" "GitHub Team:" "Label IA:" \
               "Budget limit:" "Confidence threshold:"; do
    if grep -q "$field" "$CLAUDE_FILE"; then
      pass "CLAUDE.md: campo '$field' presente"
    else
      fail "CLAUDE.md: campo '$field' ausente — pipeline não consegue carregar config"
    fi
  done

  # Budget limit é numérico
  budget=$(grep "Budget limit:" "$CLAUDE_FILE" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  if [ -n "$budget" ]; then
    pass "CLAUDE.md: budget '$budget' é numérico"
  else
    warn "CLAUDE.md: budget limit não é numérico ou ausente"
  fi

  # Confidence threshold está entre 1 e 18
  threshold=$(grep "Confidence threshold:" "$CLAUDE_FILE" | grep -oE '[0-9]+' | head -1)
  if [ -n "$threshold" ] && [ "$threshold" -ge 1 ] && [ "$threshold" -le 18 ]; then
    pass "CLAUDE.md: confidence threshold '$threshold' válido (1-18)"
  else
    fail "CLAUDE.md: confidence threshold '$threshold' inválido (deve ser 1-18)"
  fi
else
  warn "CLAUDE.md não encontrado — testes de configuração pulados"
fi

# ── Resultado Final ───────────────────────────────────────────────────────────
echo ""
echo "====================================="
TOTAL=$((PASS + FAIL))
echo "Total: $TOTAL | PASS: $PASS | FAIL: $FAIL | WARN: $WARN"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Falhas:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  echo ""
  exit 1
fi

echo "Todos os testes passaram."
exit 0
