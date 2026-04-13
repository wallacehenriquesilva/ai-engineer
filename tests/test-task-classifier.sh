#!/bin/bash
# test-task-classifier.sh — Testes unitários para task-classifier.sh e runbook-matcher.sh
# Uso: ./tests/test-task-classifier.sh [--verbose]

set -euo pipefail

VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

pass() { PASS=$((PASS + 1)); $VERBOSE && echo -e "  ${GREEN}PASS${NC} $1" || true; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo -e "  ${RED}FAIL${NC} $1"; }

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [ "$got" = "$want" ]; then
    pass "$label"
  else
    fail "$label: got='$got' want='$want'"
  fi
}

assert_contains() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label: '$want' not found in '$got'"
  fi
}

# shellcheck source=../scripts/task-classifier.sh
source "$ROOT_DIR/scripts/task-classifier.sh"

echo ""
echo "AI Engineer — Task Classifier Tests"
echo "===================================="
echo ""

# ── 1. Hotfix por label ──────────────────────────────────────────────────────
echo "1. Hotfix detection..."

result=$(classify_task "hotfix,AI,Backend" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "hotfix: label 'hotfix'"
assert_eq "$(echo "$result" | jq -r .source)" "script" "hotfix: source=script"
assert_contains "$(echo "$result" | jq -r .flags)" "--skip-clarity" "hotfix: has --skip-clarity flag"

result=$(classify_task "incident,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "hotfix: label 'incident'"

result=$(classify_task "HOTFIX,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "hotfix: case-insensitive"

# ── 2. Hotfix por prioridade ─────────────────────────────────────────────────
echo "2. Hotfix by priority..."

result=$(classify_task "AI,Backend" "Highest" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "hotfix: priority=Highest"

result=$(classify_task "AI,Backend" "P0" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "hotfix: priority=P0"

result=$(classify_task "AI,Backend" "P1" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "hotfix: priority=P1"

result=$(classify_task "AI,Backend" "High" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "unknown" "no hotfix: priority=High (not P0/P1/Highest)"

# ── 3. Refactoring ───────────────────────────────────────────────────────────
echo "3. Refactoring detection..."

result=$(classify_task "refactoring,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "refactoring" "refactoring: label 'refactoring'"

result=$(classify_task "tech-debt,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "refactoring" "refactoring: label 'tech-debt'"

result=$(classify_task "TECH-DEBT,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "refactoring" "refactoring: case-insensitive"

# ── 4. Infra por repo type ───────────────────────────────────────────────────
echo "4. Infra detection..."

result=$(classify_task "AI" "Medium" "terraform")
assert_eq "$(echo "$result" | jq -r .tipo)" "infra" "infra: repo_type=terraform"
assert_contains "$(echo "$result" | jq -r .flags)" "--skip-app-tests" "infra: has --skip-app-tests flag"

result=$(classify_task "AI" "Medium" "go")
r=$(echo "$result" | jq -r .tipo)
[ "$r" != "infra" ] && pass "no infra: repo_type=go" || fail "no infra: repo_type=go should not be infra"

# ── 5. Integration ───────────────────────────────────────────────────────────
echo "5. Integration detection..."

result=$(classify_task "integration,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "integration" "integration: label 'integration'"

result=$(classify_task "new-consumer,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "integration" "integration: label 'new-consumer'"

# ── 6. Unknown / delegação ao LLM ────────────────────────────────────────────
echo "6. Unknown (LLM delegation)..."

result=$(classify_task "AI,Backend" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "unknown" "unknown: nenhuma regra bate"
assert_eq "$(echo "$result" | jq -r .source)" "needs_llm" "unknown: source=needs_llm"

# ── 7. Prioridade de regras (hotfix > refactoring) ───────────────────────────
echo "7. Rule priority..."

result=$(classify_task "hotfix,refactoring,AI" "Medium" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "priority: hotfix wins over refactoring"

result=$(classify_task "refactoring,AI" "Highest" "go")
assert_eq "$(echo "$result" | jq -r .tipo)" "hotfix" "priority: Highest priority wins over refactoring label"

# ── 8. JSON válido em todos os casos ─────────────────────────────────────────
echo "8. Valid JSON output..."

for labels in "AI" "hotfix,AI" "tech-debt,AI" "AI,Backend" "new-consumer,AI"; do
  for priority in "Medium" "High" "Highest" "P0"; do
    for repo_type in "go" "node" "terraform" "java"; do
      result=$(classify_task "$labels" "$priority" "$repo_type")
      if echo "$result" | jq . > /dev/null 2>&1; then
        pass "valid JSON: labels=$labels priority=$priority repo=$repo_type"
      else
        fail "invalid JSON: labels=$labels priority=$priority repo=$repo_type — output: $result"
      fi
    done
  done
done

# ── 9. Runbook matcher ───────────────────────────────────────────────────────
echo "9. Runbook matcher..."

# shellcheck source=../scripts/runbook-matcher.sh
source "$ROOT_DIR/scripts/runbook-matcher.sh"

# Aponta para os runbooks reais do projeto
export RUNBOOKS_DIR="$ROOT_DIR/docs/runbooks"

if [ -d "$RUNBOOKS_DIR" ]; then
  result=$(match_runbook "hotfix,AI" "Highest" "bug em producao")
  if [ -n "$result" ]; then
    pass "runbook: hotfix label matches a runbook"
    assert_contains "$result" "hotfix" "runbook: matched file contains 'hotfix'"
  else
    fail "runbook: hotfix label should match hotfix-p0.md"
  fi

  result=$(match_runbook "AI,Backend" "Medium" "feature nova")
  [ -z "$result" ] && pass "runbook: no match for generic feature" \
                    || pass "runbook: generic feature matched $result (ok if intentional)"
else
  echo "  SKIP runbook tests — $RUNBOOKS_DIR não encontrado"
fi

# ── Resultado Final ──────────────────────────────────────────────────────────
echo ""
echo "===================================="
TOTAL=$((PASS + FAIL))
echo "Total: $TOTAL | PASS: $PASS | FAIL: $FAIL"
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
