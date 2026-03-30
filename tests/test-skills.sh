#!/bin/bash
# test-skills.sh — Testes automatizados para skills e commands do AI Engineer
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

  # Referências internas (links para examples/)
  while IFS= read -r line; do
    ref=$(echo "$line" | grep -oE '\(examples/[^)]+\)' | tr -d '()' || true)
    [ -z "$ref" ] && continue
    if [ -f "$skill_dir/$ref" ]; then
      pass "$skill_name: referência $ref válida"
    else
      fail "$skill_name: referência quebrada → $ref"
    fi
  done < "$skill_file"

  # Referências a references/
  while IFS= read -r line; do
    ref=$(echo "$line" | grep -oE '\(references/[^)]+\)' | tr -d '()' || true)
    [ -z "$ref" ] && continue
    if [ -f "$skill_dir/$ref" ]; then
      pass "$skill_name: referência $ref válida"
    else
      fail "$skill_name: referência quebrada → $ref"
    fi
  done < "$skill_file"
done

echo ""

# ── 2. Validar estrutura de commands ────────────────────────────────────────

echo "2. Validando commands..."

for cmd_file in "$ROOT_DIR"/commands/*.md; do
  cmd_name=$(basename "$cmd_file" .md)

  # Frontmatter obrigatório
  if head -1 "$cmd_file" | grep -q "^---"; then
    pass "$cmd_name: frontmatter presente"
  else
    fail "$cmd_name: frontmatter ausente"
    continue
  fi

  # Campo description
  if grep -q "^description:" "$cmd_file"; then
    pass "$cmd_name: campo 'description' presente"
  else
    fail "$cmd_name: campo 'description' ausente"
  fi

  # Campo allowed-tools
  if grep -q "^allowed-tools:" "$cmd_file"; then
    pass "$cmd_name: campo 'allowed-tools' presente"
  else
    warn "$cmd_name: campo 'allowed-tools' ausente"
  fi

  # Referências a skills existentes
  while IFS= read -r skill_ref; do
    skill_ref=$(echo "$skill_ref" | xargs)
    [ -z "$skill_ref" ] && continue
    # Normalizar: remover backticks e prefixo skill
    skill_ref_clean=$(echo "$skill_ref" | sed 's/`//g' | sed 's/^skill //')
    if [ -d "$ROOT_DIR/skills/$skill_ref_clean" ]; then
      pass "$cmd_name: skill '$skill_ref_clean' existe"
    fi
  done < <(grep -oE "skill \`[a-z-]+\`|skill [a-z-]+" "$cmd_file" 2>/dev/null || true)
done

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

# README menciona os commands principais
for cmd in engineer pr-resolve finalize run history; do
  if grep -qi "$cmd" "$ROOT_DIR/README.md" 2>/dev/null; then
    pass "README: menciona /$cmd"
  else
    warn "README: não menciona /$cmd"
  fi
done

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

echo ""

# ── 6. Validar execution-log.sh ─────────────────────────────────────────────

echo "6. Validando execution-log.sh..."

EXEC_LOG="$ROOT_DIR/scripts/execution-log.sh"
if [ -f "$EXEC_LOG" ]; then
  pass "execution-log.sh existe"

  # Funções exportadas
  for fn in exec_log_start exec_log_end exec_log_fail exec_log_history exec_log_stats; do
    if grep -q "^${fn}()" "$EXEC_LOG"; then
      pass "execution-log.sh: função $fn definida"
    else
      fail "execution-log.sh: função $fn não encontrada"
    fi
  done

  # Smoke test: source sem erro
  if (source "$EXEC_LOG" 2>/dev/null); then
    pass "execution-log.sh: source sem erros"
  else
    fail "execution-log.sh: erro ao fazer source"
  fi
else
  fail "execution-log.sh não encontrado"
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
