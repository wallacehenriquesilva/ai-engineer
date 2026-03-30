#!/bin/bash
# test-execution-log.sh — Testes unitários para o execution-log.sh
# Uso: ./tests/test-execution-log.sh

set -eo pipefail

PASS=0
FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}FAIL${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Usar diretório temporário para não poluir dados reais
export EXEC_LOG_DIR=$(mktemp -d)
trap "rm -rf $EXEC_LOG_DIR" EXIT

# Forçar modo local (serviço não está rodando no teste)
export KNOWLEDGE_SERVICE_URL="http://localhost:99999"
source "$ROOT_DIR/scripts/execution-log.sh"

echo ""
echo "Testes unitários — execution-log.sh"
echo "===================================="
echo ""

# ── Test 1: exec_log_start cria arquivo ─────────────────────────────────────

echo "1. exec_log_start..."

# exec_log_start roda em subshell quando capturado com $(), então precisamos
# chamar diretamente e ler os exports depois
exec_log_start "engineer" "AZUL-1234" "martech-worker" > /dev/null
ID="$EXEC_ID"

if [ -f "$EXEC_LOG_DIR/$ID.json" ]; then
  pass "arquivo criado: $ID.json"
else
  fail "arquivo não criado"
fi

STATUS=$(jq -r '.status' "$EXEC_LOG_DIR/$ID.json")
if [ "$STATUS" = "running" ]; then
  pass "status inicial = running"
else
  fail "status inicial esperado 'running', obtido '$STATUS'"
fi

COMMAND=$(jq -r '.command' "$EXEC_LOG_DIR/$ID.json")
if [ "$COMMAND" = "engineer" ]; then
  pass "command = engineer"
else
  fail "command esperado 'engineer', obtido '$COMMAND'"
fi

TASK=$(jq -r '.task' "$EXEC_LOG_DIR/$ID.json")
if [ "$TASK" = "AZUL-1234" ]; then
  pass "task = AZUL-1234"
else
  fail "task esperado 'AZUL-1234', obtido '$TASK'"
fi

echo ""

# ── Test 2: exec_log_end atualiza para sucesso ──────────────────────────────

echo "2. exec_log_end..."

sleep 1
exec_log_end "PR aberta com sucesso" "https://github.com/org/repo/pull/1" "0.4500" "1000" "500" "200" "300"

STATUS=$(jq -r '.status' "$EXEC_FILE")
if [ "$STATUS" = "success" ]; then
  pass "status = success"
else
  fail "status esperado 'success', obtido '$STATUS'"
fi

PR=$(jq -r '.pr_url' "$EXEC_FILE")
if [ "$PR" = "https://github.com/org/repo/pull/1" ]; then
  pass "pr_url gravado"
else
  fail "pr_url não gravado corretamente"
fi

DUR=$(jq -r '.duration_seconds' "$EXEC_FILE")
if [ "$DUR" -ge 1 ]; then
  pass "duration_seconds >= 1 ($DUR)"
else
  fail "duration_seconds deveria ser >= 1, obtido $DUR"
fi

COST=$(jq -r '.cost_usd' "$EXEC_FILE")
# jq preserva o número como foi parseado — 0.45 ou 0.4500 são equivalentes
COST_CHECK=$(echo "$COST" | awk '{printf "%.2f", $1}')
if [ "$COST_CHECK" = "0.45" ]; then
  pass "cost_usd = $COST"
else
  fail "cost_usd esperado '0.45', obtido '$COST'"
fi

echo ""

# ── Test 3: exec_log_fail atualiza para falha ───────────────────────────────

echo "3. exec_log_fail..."

exec_log_start "run" "AZUL-5678" "notification-hub" > /dev/null
ID2="$EXEC_ID"
sleep 1
exec_log_fail 9 "SonarQube timeout" "https://github.com/org/repo/pull/2"

STATUS=$(jq -r '.status' "$EXEC_FILE")
if [ "$STATUS" = "failure" ]; then
  pass "status = failure"
else
  fail "status esperado 'failure', obtido '$STATUS'"
fi

STEP=$(jq -r '.failed_step' "$EXEC_FILE")
if [ "$STEP" = "9" ]; then
  pass "failed_step = 9"
else
  fail "failed_step esperado '9', obtido '$STEP'"
fi

REASON=$(jq -r '.failure_reason' "$EXEC_FILE")
if [ "$REASON" = "SonarQube timeout" ]; then
  pass "failure_reason gravado"
else
  fail "failure_reason não gravado corretamente"
fi

echo ""

# ── Test 4: exec_log_history retorna execuções ──────────────────────────────

echo "4. exec_log_history..."

HISTORY=$(exec_log_history --limit 10)
COUNT=$(echo "$HISTORY" | jq 'length')

if [ "$COUNT" -ge 2 ]; then
  pass "history retorna >= 2 execuções ($COUNT)"
else
  fail "history deveria retornar >= 2, obtido $COUNT"
fi

# Filtro por status
SUCCESS_ONLY=$(exec_log_history --status success)
S_COUNT=$(echo "$SUCCESS_ONLY" | jq 'length')

if [ "$S_COUNT" -ge 1 ]; then
  pass "filtro --status success funciona ($S_COUNT)"
else
  fail "filtro --status success deveria retornar >= 1"
fi

echo ""

# ── Test 5: exec_log_stats retorna estatísticas ─────────────────────────────

echo "5. exec_log_stats..."

STATS=$(exec_log_stats 30)

TOTAL=$(echo "$STATS" | jq '.total')
if [ "$TOTAL" -ge 2 ]; then
  pass "stats.total >= 2 ($TOTAL)"
else
  fail "stats.total deveria ser >= 2, obtido $TOTAL"
fi

SUCCESS_RATE=$(echo "$STATS" | jq '.success_rate')
if [ "$SUCCESS_RATE" -ge 0 ] && [ "$SUCCESS_RATE" -le 100 ]; then
  pass "stats.success_rate entre 0-100 ($SUCCESS_RATE%)"
else
  fail "stats.success_rate fora do range: $SUCCESS_RATE"
fi

echo ""

# ── Relatório ────────────────────────────────────────────────────────────────

TOTAL_TESTS=$((PASS + FAIL))
echo "════════════════════════════════"
echo "  Resultado: $PASS passed, $FAIL failed ($TOTAL_TESTS total)"
echo "════════════════════════════════"
echo ""

exit $FAIL
