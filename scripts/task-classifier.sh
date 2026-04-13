#!/bin/bash
# task-classifier.sh — Classifica task por sinais explicitos (labels, prioridade, repo type)
#
# Camada 1 da classificacao hibrida. Retorna JSON se bater regra explicita,
# ou "unknown" para delegar ao LLM (camada 2 no orchestrator).
#
# Uso:
#   source scripts/task-classifier.sh
#   classify_task "hotfix,AI,Backend" "Highest" "go"
#   → {"tipo":"hotfix","flags":"--skip-clarity --fast-ci --min-reviewers 1","runbook":"hotfix-p0.md","source":"script"}

classify_task() {
  local labels="$1" priority="$2" repo_type="$3"

  # Hotfix — label explicita ou prioridade critica
  if echo "$labels" | grep -qiE "hotfix|incident"; then
    echo '{"tipo":"hotfix","flags":"--skip-clarity --fast-ci --min-reviewers 1","runbook":"hotfix-p0.md","source":"script"}'
    return
  fi
  if echo "$priority" | grep -qiE "Highest|P0|P1"; then
    echo '{"tipo":"hotfix","flags":"--skip-clarity --fast-ci --min-reviewers 1","runbook":"hotfix-p0.md","source":"script"}'
    return
  fi

  # Refactoring — label explicita
  if echo "$labels" | grep -qiE "refactoring|tech-debt"; then
    echo '{"tipo":"refactoring","flags":"--runbook large-refactoring.md","runbook":"large-refactoring.md","source":"script"}'
    return
  fi

  # Infra — tipo de repo
  if [ "$repo_type" = "terraform" ]; then
    echo '{"tipo":"infra","flags":"--skip-app-tests","runbook":"","source":"script"}'
    return
  fi

  # Integration — label explicita
  if echo "$labels" | grep -qiE "integration|new-consumer"; then
    echo '{"tipo":"integration","flags":"--runbook new-integration.md","runbook":"new-integration.md","source":"script"}'
    return
  fi

  # Nenhuma regra bateu — delegar ao LLM
  echo '{"tipo":"unknown","source":"needs_llm"}'
}
