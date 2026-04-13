#!/bin/bash
# runbook-matcher.sh — Seleciona runbook por match de frontmatter
#
# Parseia o frontmatter YAML dos runbooks e compara com sinais da task.
# Retorna o path do runbook que mais combina, ou vazio se nenhum.
#
# Uso:
#   source scripts/runbook-matcher.sh
#   match_runbook "hotfix,AI" "Highest" "bug em producao"
#   → docs/runbooks/hotfix-p0.md

RUNBOOKS_DIR="${RUNBOOKS_DIR:-$HOME/.ai-engineer/docs/runbooks}"

match_runbook() {
  local labels="$1" priority="$2" description="$3"

  [ -d "$RUNBOOKS_DIR" ] || return 0

  for runbook in "$RUNBOOKS_DIR"/*.md; do
    [ -f "$runbook" ] || continue

    # Extrair frontmatter (entre --- e ---)
    local frontmatter
    frontmatter=$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$runbook")

    [ -z "$frontmatter" ] && continue

    # Extrair triggers.labels
    local trigger_labels
    trigger_labels=$(echo "$frontmatter" | grep "labels:" | sed 's/.*\[//;s/\].*//' | tr ',' '\n' | tr -d ' ')

    # Match por labels
    if [ -n "$trigger_labels" ]; then
      while IFS= read -r tlabel; do
        [ -z "$tlabel" ] && continue
        if echo "$labels" | grep -qiE "$tlabel"; then
          echo "$runbook"
          return 0
        fi
      done <<< "$trigger_labels"
    fi

    # Extrair triggers.priority
    local trigger_priority
    trigger_priority=$(echo "$frontmatter" | grep "priority:" | sed 's/.*\[//;s/\].*//' | tr ',' '\n' | tr -d ' ')

    # Match por prioridade
    if [ -n "$trigger_priority" ]; then
      while IFS= read -r tprio; do
        [ -z "$tprio" ] && continue
        if echo "$priority" | grep -qiE "$tprio"; then
          echo "$runbook"
          return 0
        fi
      done <<< "$trigger_priority"
    fi

    # Extrair triggers.keywords
    local trigger_keywords
    trigger_keywords=$(echo "$frontmatter" | grep "keywords:" | sed 's/.*\[//;s/\].*//' | tr ',' '\n' | sed 's/^ *//')

    # Match por keywords na descricao
    if [ -n "$trigger_keywords" ] && [ -n "$description" ]; then
      while IFS= read -r tkw; do
        [ -z "$tkw" ] && continue
        if echo "$description" | grep -qiE "$tkw"; then
          echo "$runbook"
          return 0
        fi
      done <<< "$trigger_keywords"
    fi
  done

  # Nenhum match
  echo ""
}
