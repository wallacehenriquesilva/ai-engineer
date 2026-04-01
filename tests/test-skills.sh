#!/bin/bash
# test-skills.sh — Testes automatizados para skills do AI Engineer
# Uso: ./tests/test-skills.sh [--verbose]
#
# Valida estrutura, campos obrigatórios, referências e consistência.

set -euo pipefail

VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

PASS=0
FAIL=0
WARN=0
ERRORS=()

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { PASS=$((PASS + 1)); $VERBOSE && echo -e "  ${GREEN}PASS${NC} $1" || true; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo -e "  ${RED}FAIL${NC} $1"; }
warn() { WARN=$((WARN + 1)); echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "AI Engineer — Test Suite"
echo "========================"
echo ""

# ── 1. Validar estrutura de skills ──────────────────────────────────────────

echo "1. Validando skills..."

for skill_dir in "$ROOT_DIR"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  skill_file="$skill_dir/SKILL.md"

  # SKILL.md existe
  if [ -f "$skill_file" ]; then
    pass "$skill_name: SKILL.md existe"
  else
    fail "$skill_name: SKILL.md não encontrado"
    continue
  fi

  # Frontmatter obrigatório
  if head -1 "$skill_file" | grep -q "^---"; then
    pass "$skill_name: frontmatter presente"
  else
    fail "$skill_name: frontmatter ausente (deve começar com ---)"
    continue
  fi

  # Campo name
  if grep -q "^name:" "$skill_file"; then
    pass "$skill_name: campo 'name' presente"
  else
    fail "$skill_name: campo 'name' ausente no frontmatter"
  fi

  # Campo description
  if grep -q "^description:" "$skill_file"; then
    pass "$skill_name: campo 'description' presente"
  else
    fail "$skill_name: campo 'description' ausente no frontmatter"
  fi

  # Campo allowed-tools
  if grep -q "^allowed-tools:" "$skill_file"; then
    pass "$skill_name: campo 'allowed-tools' presente"
  else
    warn "$skill_name: campo 'allowed-tools' ausente — skill pode não funcionar corretamente"
  fi

  # Campo version
  if awk '/^---$/{n++; next} n==1' "$skill_file" | grep -q "^version:"; then
    pass "$skill_name: campo 'version' presente"
  else
    warn "$skill_name: campo 'version' ausente (recomendado)"
  fi

  # Campo depends-on
  if awk '/^---$/{n++; next} n==1' "$skill_file" | grep -q "^depends-on:"; then
    pass "$skill_name: campo 'depends-on' presente"
  else
    warn "$skill_name: campo 'depends-on' ausente (recomendado)"
  fi

  # Campo triggers
  if awk '/^---$/{n++; next} n==1' "$skill_file" | grep -q "^triggers:"; then
    pass "$skill_name: campo 'triggers' presente"
  else
    warn "$skill_name: campo 'triggers' ausente (recomendado)"
  fi

  # Referências internas (examples/, references/, templates/)
  for ref_dir in examples references templates; do
    while IFS= read -r line; do
      ref=$(echo "$line" | grep -oE "\(${ref_dir}/[^)]+\)" | tr -d '()' || true)
      [ -z "$ref" ] && continue
      if [ -f "$skill_dir/$ref" ]; then
        pass "$skill_name: referência $ref válida"
      else
        fail "$skill_name: referência quebrada → $ref"
      fi
    done < "$skill_file"
  done

  # Valida depends-on aponta para skills existentes
  in_frontmatter=false
  in_depends=false
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if $in_frontmatter; then break; fi
      in_frontmatter=true
      continue
    fi
    $in_frontmatter || continue

    if echo "$line" | grep -q "^depends-on:"; then
      # depends-on: [] — lista vazia inline, pular
      if echo "$line" | grep -q "\[\]"; then
        continue
      fi
      in_depends=true
      continue
    fi

    if $in_depends; then
      # Se a linha começa com "  - ", é um item da lista YAML
      if echo "$line" | grep -qE '^[[:space:]]+-[[:space:]]'; then
        dep=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | xargs)
        if [ -z "$dep" ] || [ "$dep" = "[]" ]; then
          in_depends=false
          continue
        fi
        if [ -d "$ROOT_DIR/skills/$dep" ]; then
          pass "$skill_name: depends-on '$dep' existe"
        else
          fail "$skill_name: depends-on '$dep' não encontrada em skills/"
        fi
      else
        # Linha não é item de lista — saiu do depends-on
        in_depends=false
      fi
    fi
  done < "$skill_file"
done

echo ""

# ── 2. Executar lint-skills.sh ─────────────────────────────────────────────

echo "2. Executando lint de skills..."

LINT_SCRIPT="$ROOT_DIR/scripts/lint-skills.sh"
if [ -f "$LINT_SCRIPT" ] && [ -x "$LINT_SCRIPT" ]; then
  if "$LINT_SCRIPT" --ci >/dev/null 2>&1; then
    pass "lint-skills.sh: todas as skills passaram"
  else
    fail "lint-skills.sh: uma ou mais skills falharam na validação"
  fi
else
  warn "lint-skills.sh não encontrado ou não executável — pulando"
fi

echo ""

# ── 3. Validar scripts ─────────────────────────────────────────────────────

echo "3. Validando scripts..."

for script in "$ROOT_DIR"/scripts/*.sh; do
  script_name=$(basename "$script")

  # É executável ou tem shebang
  if head -1 "$script" | grep -q "^#!/bin/bash\|^#!/usr/bin/env bash"; then
    pass "$script_name: shebang presente"
  else
    fail "$script_name: shebang ausente"
  fi

  # Shellcheck (se disponível)
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S warning "$script" >/dev/null 2>&1; then
      pass "$script_name: shellcheck OK"
    else
      warn "$script_name: shellcheck reportou warnings"
    fi
  fi
done

echo ""

# ── 4. Validar knowledge-service ────────────────────────────────────────────

echo "4. Validando knowledge-service..."

KS_DIR="$ROOT_DIR/knowledge-service"

if [ -f "$KS_DIR/go.mod" ]; then
  pass "knowledge-service: go.mod existe"

  # Verifica se compila
  if (cd "$KS_DIR" && go build ./... 2>/dev/null); then
    pass "knowledge-service: compila com sucesso"
  else
    fail "knowledge-service: falha na compilação"
  fi
else
  fail "knowledge-service: go.mod não encontrado"
fi

if [ -f "$KS_DIR/docker-compose.yml" ]; then
  pass "knowledge-service: docker-compose.yml existe"
else
  fail "knowledge-service: docker-compose.yml não encontrado"
fi

if [ -f "$KS_DIR/Dockerfile" ]; then
  pass "knowledge-service: Dockerfile existe"
else
  fail "knowledge-service: Dockerfile não encontrado"
fi

echo ""

# ── 5. Validar consistência geral ──────────────────────────────────────────

echo "5. Validando consistência..."

# PROJECT.md menciona os commands principais
PROJECT_FILE="$ROOT_DIR/docs/PROJECT.md"
if [ -f "$PROJECT_FILE" ]; then
  for cmd in engineer pr-resolve finalize run history; do
    if grep -qi "$cmd" "$PROJECT_FILE" 2>/dev/null; then
      pass "PROJECT.md: menciona /$cmd"
    else
      warn "PROJECT.md: não menciona /$cmd"
    fi
  done
else
  warn "docs/PROJECT.md não encontrado"
fi

# Makefile targets existem
for target in setup up down scan watch install test clean; do
  if grep -q "^$target:" "$ROOT_DIR/Makefile" 2>/dev/null; then
    pass "Makefile: target '$target' existe"
  else
    warn "Makefile: target '$target' ausente"
  fi
done

# .env.example existe
if [ -f "$ROOT_DIR/.env.example" ]; then
  pass ".env.example existe"
else
  warn ".env.example não encontrado"
fi

# install.sh existe e é válido
if [ -f "$ROOT_DIR/install.sh" ]; then
  pass "install.sh existe"
  if head -1 "$ROOT_DIR/install.sh" | grep -q "^#!/bin/bash\|^#!/usr/bin/env bash"; then
    pass "install.sh: shebang presente"
  else
    warn "install.sh: shebang ausente"
  fi
else
  fail "install.sh não encontrado"
fi

# CLAUDE.md.template existe e tem referência de campos
TEMPLATE="$ROOT_DIR/docs/CLAUDE.md.template"
if [ -f "$TEMPLATE" ]; then
  pass "CLAUDE.md.template existe"
  if grep -q "REFERÊNCIA DE CAMPOS" "$TEMPLATE"; then
    pass "CLAUDE.md.template: referência de campos presente"
  else
    warn "CLAUDE.md.template: referência de campos ausente"
  fi
else
  fail "CLAUDE.md.template não encontrado"
fi

echo ""

# ── 6. Validar execution-log.sh ─────────────────────────────────────────────

echo "6. Validando execution-log.sh..."

EXEC_LOG="$ROOT_DIR/scripts/execution-log.sh"
if [ -f "$EXEC_LOG" ]; then
  pass "execution-log.sh existe"

  # Funções exportadas
  for fn in exec_log_start exec_log_end exec_log_fail exec_log_history exec_log_stats exec_handoff_save exec_handoff_load exec_handoff_get exec_handoff_clean; do
    if grep -q "^${fn}()" "$EXEC_LOG"; then
      pass "execution-log.sh: função $fn definida"
    else
      fail "execution-log.sh: função $fn não encontrada"
    fi
  done

  # Smoke test: source sem erro
  if (EXEC_LOG_DIR=$(mktemp -d) HANDOFF_DIR=$(mktemp -d) source "$EXEC_LOG" 2>/dev/null); then
    pass "execution-log.sh: source sem erros"
  else
    fail "execution-log.sh: erro ao fazer source"
  fi
else
  fail "execution-log.sh não encontrado"
fi

echo ""

# ── 7. Validar handoff templates ────────────────────────────────────────────

echo "7. Validando handoff templates..."

HANDOFF_DIR="$ROOT_DIR/skills/run/templates"
if [ -d "$HANDOFF_DIR" ]; then
  pass "run/templates/ existe"

  for template in engineer-to-pr-resolve.md pr-resolve-to-finalize.md escalation.md; do
    if [ -f "$HANDOFF_DIR/$template" ]; then
      pass "handoff template: $template existe"
    else
      fail "handoff template: $template não encontrado"
    fi
  done
else
  fail "skills/run/templates/ não encontrado"
fi

echo ""

# ── 8. Validar runbooks ────────────────────────────────────────────────────

echo "8. Validando runbooks..."

RUNBOOKS_DIR="$ROOT_DIR/docs/runbooks"
if [ -d "$RUNBOOKS_DIR" ]; then
  pass "docs/runbooks/ existe"

  for runbook in hotfix-p0.md large-refactoring.md new-integration.md; do
    if [ -f "$RUNBOOKS_DIR/$runbook" ]; then
      pass "runbook: $runbook existe"
    else
      warn "runbook: $runbook não encontrado"
    fi
  done
else
  warn "docs/runbooks/ não encontrado"
fi

echo ""

# ── Relatório Final ─────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))
echo "════════════════════════════════"
echo "  Resultado: $PASS passed, $FAIL failed, $WARN warnings ($TOTAL total)"
echo "════════════════════════════════"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Falhas:"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
fi

echo ""
exit $FAIL
