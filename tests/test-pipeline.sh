#!/bin/bash
# test-pipeline.sh — Testes de cenários do pipeline (sem LLM real)
#
# Simula o comportamento do orchestrator injetando respostas mock dos sub-agents.
# Valida as decisões do pipeline: encerrar, retornar, fazer retry.
#
# Uso:
#   ./tests/test-pipeline.sh [--verbose] [--scenario <nome>]
#
# Cenários disponíveis:
#   no_task           → task-fetcher retorna no_task → pipeline encerra
#   needs_clarity     → task com score baixo → pipeline comenta e encerra
#   evaluator_retry   → evaluator FAIL na 1ª, PASS na 2ª → pipeline retenta
#   tester_fail       → tester falha → engineer recebe feedback e retenta
#   success           → fluxo completo sem falhas → PR criada
#   all               → roda todos os cenários

set -euo pipefail

VERBOSE=false
SCENARIO="all"

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose) VERBOSE=true; shift ;;
    --scenario) SCENARIO="$2"; shift 2 ;;
    *) echo "Opção desconhecida: $1"; exit 1 ;;
  esac
done

PASS=0
FAIL=0
ERRORS=()

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1"); echo -e "  ${RED}FAIL${NC} $1"; }
info() { $VERBOSE && echo -e "  ${YELLOW}INFO${NC} $1" || true; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Simula o comportamento do orchestrator para um dado cenário
# sem chamar LLMs reais. Usa fixtures JSON como respostas dos sub-agents.
run_scenario() {
  local scenario="$1"
  local fixture_file="$FIXTURES_DIR/$scenario.json"

  if [ ! -f "$fixture_file" ]; then
    fail "$scenario: fixture não encontrada ($fixture_file)"
    return 1
  fi

  # Carrega fixture
  local fixture
  fixture=$(cat "$fixture_file")

  # Extrai configurações do cenário
  local description expected_status expect_jira_comment expect_pr_created expect_retries
  description=$(echo "$fixture" | jq -r '.description')
  expected_status=$(echo "$fixture" | jq -r '.expected.final_status')
  expect_jira_comment=$(echo "$fixture" | jq -r '.expected.jira_comment // false')
  expect_pr_created=$(echo "$fixture" | jq -r '.expected.pr_created // false')
  expect_retries=$(echo "$fixture" | jq -r '.expected.engineer_retries // 0')

  info "Cenário: $description"

  # Simula decisões do orchestrator baseado nos retornos mock
  local task_fetcher_response engineer_call_count pr_created jira_commented final_status

  task_fetcher_response=$(echo "$fixture" | jq -r '.mock_responses.task_fetcher')
  local task_status
  task_status=$(echo "$task_fetcher_response" | jq -r '.status')

  # Passo 1: task-fetcher
  info "  → task-fetcher: $task_status"
  if [ "$task_status" = "no_task" ]; then
    final_status="no_task"
    jira_commented=false
    pr_created=false
    engineer_call_count=0
  elif [ "$task_status" = "success" ]; then
    # Passo 3: clarity check
    local clarity_score
    clarity_score=$(echo "$fixture" | jq -r '.mock_responses.clarity_score // 18')
    local clarity_threshold=15
    info "  → clarity: $clarity_score/18 (threshold: $clarity_threshold)"

    if [ "$clarity_score" -lt "$clarity_threshold" ]; then
      final_status="needs_clarity"
      jira_commented=true
      pr_created=false
      engineer_call_count=0
    else
      # Passos 5-9: engineer → tester → evaluator → pr
      engineer_call_count=0
      local evaluator_responses tester_ok max_evaluator_cycles=2
      evaluator_responses=$(echo "$fixture" | jq -r '.mock_responses.evaluator_verdicts // ["PASS"]')
      tester_ok=$(echo "$fixture" | jq -r 'if (.mock_responses.tester_pass | type) == "boolean" then (.mock_responses.tester_pass | tostring) else "true" end')

      local current_cycle=0
      local loop_done=false

      while ! $loop_done && [ $current_cycle -lt $max_evaluator_cycles ]; do
        engineer_call_count=$((engineer_call_count + 1))
        info "  → engineer call #$engineer_call_count"

        # Tester
        if [ "$tester_ok" = "true" ] || [ $engineer_call_count -gt 1 ]; then
          info "  → tester: pass"
        else
          info "  → tester: fail → feedback para engineer"
          # Retry engineer com feedback
          engineer_call_count=$((engineer_call_count + 1))
          info "  → engineer call #$engineer_call_count (retry por tester)"
        fi

        # Evaluator
        local evaluator_verdict
        evaluator_verdict=$(echo "$evaluator_responses" | jq -r ".[$current_cycle] // \"PASS\"")
        info "  → evaluator[$current_cycle]: $evaluator_verdict"

        if [ "$evaluator_verdict" = "PASS" ]; then
          loop_done=true
          pr_created=true
          final_status="success"
        else
          current_cycle=$((current_cycle + 1))
          if [ $current_cycle -ge $max_evaluator_cycles ]; then
            loop_done=true
            pr_created=false
            final_status="failed"
            info "  → max cycles ($max_evaluator_cycles) atingido"
          fi
        fi
      done

      jira_commented=false
    fi
  else
    final_status="failed"
    jira_commented=false
    pr_created=false
    engineer_call_count=0
  fi

  # Validações
  if [ "$final_status" = "$expected_status" ]; then
    pass "$scenario: status final '$final_status' correto"
  else
    fail "$scenario: status final '$final_status' ≠ esperado '$expected_status'"
  fi

  if [ "$expect_jira_comment" = "true" ] && [ "$jira_commented" = "true" ]; then
    pass "$scenario: Jira comment feito (esperado)"
  elif [ "$expect_jira_comment" = "false" ] && [ "$jira_commented" = "false" ]; then
    pass "$scenario: Jira comment não feito (esperado)"
  elif [ "$expect_jira_comment" = "true" ] && [ "$jira_commented" = "false" ]; then
    fail "$scenario: Jira comment esperado mas não feito"
  elif [ "$expect_jira_comment" = "false" ] && [ "$jira_commented" = "true" ]; then
    fail "$scenario: Jira comment não esperado mas foi feito"
  fi

  if [ "$expect_pr_created" = "true" ] && [ "$pr_created" = "true" ]; then
    pass "$scenario: PR criada (esperado)"
  elif [ "$expect_pr_created" = "false" ] && [ "$pr_created" = "false" ]; then
    pass "$scenario: PR não criada (esperado)"
  elif [ "$expect_pr_created" = "true" ] && [ "$pr_created" = "false" ]; then
    fail "$scenario: PR esperada mas não criada"
  else
    fail "$scenario: PR não esperada mas foi criada"
  fi

  if [ "$expect_retries" -gt 0 ]; then
    local expected_calls=$((expect_retries + 1))
    if [ "$engineer_call_count" -ge "$expected_calls" ]; then
      pass "$scenario: engineer chamado $engineer_call_count vez(es) (retry funcionou)"
    else
      fail "$scenario: engineer deveria ter sido chamado $expected_calls vez(es), foi $engineer_call_count"
    fi
  fi
}

# ── Criar fixtures se não existirem ───────────────────────────────────────────
mkdir -p "$FIXTURES_DIR"

# Fixture: no_task
cat > "$FIXTURES_DIR/no_task.json" << 'EOF'
{
  "description": "task-fetcher retorna no_task — pipeline deve encerrar imediatamente",
  "mock_responses": {
    "task_fetcher": {"status": "no_task"}
  },
  "expected": {
    "final_status": "no_task",
    "jira_comment": false,
    "pr_created": false,
    "engineer_retries": 0
  }
}
EOF

# Fixture: needs_clarity
cat > "$FIXTURES_DIR/needs_clarity.json" << 'EOF'
{
  "description": "Task com score de clareza 8/18 — pipeline comenta no Jira e encerra",
  "mock_responses": {
    "task_fetcher": {
      "status": "success",
      "task_id": "AZUL-9999",
      "task_summary": "Fazer algo vago",
      "repo_name": "martech-worker",
      "repo_type": "go"
    },
    "clarity_score": 8
  },
  "expected": {
    "final_status": "needs_clarity",
    "jira_comment": true,
    "pr_created": false,
    "engineer_retries": 0
  }
}
EOF

# Fixture: success
cat > "$FIXTURES_DIR/success.json" << 'EOF'
{
  "description": "Fluxo completo sem falhas — PR criada",
  "mock_responses": {
    "task_fetcher": {
      "status": "success",
      "task_id": "AZUL-1234",
      "task_summary": "Adicionar campo X ao consumer Y",
      "repo_name": "martech-worker",
      "repo_type": "go"
    },
    "clarity_score": 16,
    "tester_pass": true,
    "evaluator_verdicts": ["PASS"]
  },
  "expected": {
    "final_status": "success",
    "jira_comment": false,
    "pr_created": true,
    "engineer_retries": 0
  }
}
EOF

# Fixture: evaluator_retry
cat > "$FIXTURES_DIR/evaluator_retry.json" << 'EOF'
{
  "description": "Evaluator FAIL na 1ª chamada, PASS na 2ª — engineer deve ser chamado 2x",
  "mock_responses": {
    "task_fetcher": {
      "status": "success",
      "task_id": "AZUL-5678",
      "task_summary": "Corrigir bug no handler",
      "repo_name": "martech-worker",
      "repo_type": "go"
    },
    "clarity_score": 16,
    "tester_pass": true,
    "evaluator_verdicts": ["FAIL", "PASS"]
  },
  "expected": {
    "final_status": "success",
    "jira_comment": false,
    "pr_created": true,
    "engineer_retries": 1
  }
}
EOF

# Fixture: evaluator_fail_max_cycles
cat > "$FIXTURES_DIR/evaluator_fail_max_cycles.json" << 'EOF'
{
  "description": "Evaluator FAIL em ambos os ciclos — pipeline encerra com falha",
  "mock_responses": {
    "task_fetcher": {
      "status": "success",
      "task_id": "AZUL-5679",
      "task_summary": "Feature complexa",
      "repo_name": "martech-worker",
      "repo_type": "go"
    },
    "clarity_score": 16,
    "tester_pass": true,
    "evaluator_verdicts": ["FAIL", "FAIL"]
  },
  "expected": {
    "final_status": "failed",
    "jira_comment": false,
    "pr_created": false,
    "engineer_retries": 1
  }
}
EOF

# Fixture: tester_fail
cat > "$FIXTURES_DIR/tester_fail.json" << 'EOF'
{
  "description": "Tester falha na 1ª tentativa — engineer recebe feedback e retenta",
  "mock_responses": {
    "task_fetcher": {
      "status": "success",
      "task_id": "AZUL-5680",
      "task_summary": "Implementar consumer SQS",
      "repo_name": "martech-worker",
      "repo_type": "go"
    },
    "clarity_score": 16,
    "tester_pass": false,
    "evaluator_verdicts": ["PASS"]
  },
  "expected": {
    "final_status": "success",
    "jira_comment": false,
    "pr_created": true,
    "engineer_retries": 1
  }
}
EOF

# ── Rodar cenários ────────────────────────────────────────────────────────────

echo ""
echo "AI Engineer — Pipeline Scenario Tests"
echo "======================================="
echo ""

ALL_SCENARIOS=(no_task needs_clarity success evaluator_retry evaluator_fail_max_cycles tester_fail)

if [ "$SCENARIO" = "all" ]; then
  for s in "${ALL_SCENARIOS[@]}"; do
    echo "► $s"
    run_scenario "$s"
    echo ""
  done
else
  echo "► $SCENARIO"
  run_scenario "$SCENARIO"
  echo ""
fi

# ── Resultado Final ───────────────────────────────────────────────────────────
echo "======================================="
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

echo "Todos os cenários passaram."
exit 0
