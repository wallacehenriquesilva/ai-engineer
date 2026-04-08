#!/bin/bash
# knowledge-client.sh — Cliente unificado para o knowledge-service
#
# Tenta o serviço HTTP (PostgreSQL + pgvector) primeiro.
# Se indisponível, usa SQLite local como fallback.
#
# Uso: source scripts/knowledge-client.sh
#
# O modo é detectado automaticamente:
#   - "remote" → knowledge-service HTTP disponível (busca semântica)
#   - "local"  → SQLite em ~/.ai-engineer/knowledge.db (busca por texto)
#
# Para forçar um modo: export KNOWLEDGE_MODE=local (ou remote)

KNOWLEDGE_URL="${KNOWLEDGE_SERVICE_URL:-http://localhost:8080}"
AGENT_ID="${AGENT_ID:-$(hostname)}"

# ── Detectar modo ───────────────────────────────────────────────────────────

_kc_detect_mode() {
  if [ "${KNOWLEDGE_MODE:-}" = "local" ]; then
    echo "local"
    return
  fi
  if [ "${KNOWLEDGE_MODE:-}" = "remote" ]; then
    echo "remote"
    return
  fi
  # Auto-detect: testa health do serviço com timeout de 2s
  if curl -sf --max-time 2 "$KNOWLEDGE_URL/health" >/dev/null 2>&1; then
    echo "remote"
  else
    echo "local"
  fi
}

KC_MODE="$(_kc_detect_mode)"

# Inicializa SQLite se modo local
if [ "$KC_MODE" = "local" ]; then
  _KC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  if [ -f "$_KC_SCRIPT_DIR/knowledge-local.sh" ]; then
    source "$_KC_SCRIPT_DIR/knowledge-local.sh"
  elif [ -f "$HOME/.ai-engineer/scripts/knowledge-local.sh" ]; then
    source "$HOME/.ai-engineer/scripts/knowledge-local.sh"
  fi
  kl_init 2>/dev/null
fi

# ── Learnings ───────────────────────────────────────────────────────────────

# Registra um aprendizado (ou incrementa times_seen se pattern já existir)
# Args: repo, task, step, error_type, error_message, root_cause, solution, pattern
kc_learning_create() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X POST "$KNOWLEDGE_URL/learnings" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg repo "$1" --arg task "$2" --argjson step "${3:-0}" \
        --arg error_type "$4" --arg error_message "$5" \
        --arg root_cause "$6" --arg solution "$7" --arg pattern "$8" \
        --arg agent_id "$AGENT_ID" \
        '{repo:$repo, task:$task, step:$step, error_type:$error_type,
          error_message:$error_message, root_cause:$root_cause,
          solution:$solution, pattern:$pattern, agent_id:$agent_id}')"
  else
    kl_learning_create "$@"
  fi
}

# Busca learnings (semântica no remote, texto no local)
# Args: query [repo] [top_k]
kc_learning_search() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X POST "$KNOWLEDGE_URL/learnings/search" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg q "$1" --arg repo "${2:-}" --argjson top_k "${3:-5}" \
        '{query:$q, repo:(if $repo == "" then null else $repo end), top_k:$top_k, unresolved_only:true}')"
  else
    kl_learning_search "$@"
  fi
}

# Lista learnings filtrados por repo
# Args: [repo]
kc_learning_list() {
  if [ "$KC_MODE" = "remote" ]; then
    local params=""
    [ -n "${1:-}" ] && params="?repo=$1&unresolved=true" || params="?unresolved=true"
    curl -sf "$KNOWLEDGE_URL/learnings$params"
  else
    kl_learning_list "$@"
  fi
}

# Lista learnings candidatos a promoção (times_seen >= threshold)
kc_learning_promotions() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf "$KNOWLEDGE_URL/learnings/promotions"
  else
    kl_learning_promotions
  fi
}

# Marca learning como resolvido
# Args: learning_id
kc_learning_resolve() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X PUT "$KNOWLEDGE_URL/learnings/$1/resolve"
  else
    kl_learning_resolve "$1"
  fi
}

# Marca learning como promovido
# Args: learning_id
kc_learning_promote() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X PUT "$KNOWLEDGE_URL/learnings/$1/promote"
  else
    kl_learning_promote "$1"
  fi
}

# ── Executions ──────────────────────────────────────────────────────────────

# Inicia uma execução — retorna JSON com {id, status}
# Args: command, task, repo
kc_exec_start() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X POST "$KNOWLEDGE_URL/executions" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg cmd "$1" --arg task "${2:-}" --arg repo "${3:-}" \
        --arg agent_id "$AGENT_ID" \
        '{command:$cmd, task:$task, repo:$repo, agent_id:$agent_id}')"
  else
    kl_exec_start "$@"
  fi
}

# Finaliza execução com sucesso
# Args: id, result, [pr_url], [cost], [input], [cache_write], [cache_read], [output]
kc_exec_end() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X PUT "$KNOWLEDGE_URL/executions/$1" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg status "success" --arg result "${2:-}" \
        --arg pr_url "${3:-}" --argjson cost "${4:-0}" \
        --argjson input "${5:-0}" --argjson cw "${6:-0}" \
        --argjson cr "${7:-0}" --argjson out "${8:-0}" \
        '{status:$status, result:$result, pr_url:$pr_url,
          cost_usd:$cost,
          tokens:{input:$input, cache_write:$cw, cache_read:$cr, output:$out}}')"
  else
    kl_exec_end "$@"
  fi
}

# Finaliza execução com falha
# Args: id, step, reason, [pr_url]
kc_exec_fail() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X PUT "$KNOWLEDGE_URL/executions/$1" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg status "failure" --argjson step "${2:-0}" \
        --arg reason "${3:-}" --arg pr_url "${4:-}" \
        '{status:$status, failed_step:$step, failure_reason:$reason, pr_url:$pr_url}')"
  else
    kl_exec_fail "$@"
  fi
}

# Estatísticas agregadas
# Args: [days]
kc_exec_stats() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf "$KNOWLEDGE_URL/executions/stats?days=${1:-30}"
  else
    kl_exec_stats "$@"
  fi
}

# Lista execuções
# Args: [limit] [status] [command] [agent_id]
kc_exec_list() {
  if [ "$KC_MODE" = "remote" ]; then
    local params="limit=${1:-20}"
    [ -n "${2:-}" ] && params="$params&status=$2"
    [ -n "${3:-}" ] && params="$params&command=$3"
    [ -n "${4:-}" ] && params="$params&agent_id=$4"
    curl -sf "$KNOWLEDGE_URL/executions?$params"
  else
    kl_exec_list "$@"
  fi
}

# ── Knowledge (wrappers) ──────────────────────────────────────────────────

# Busca semântica no knowledge base de repos
# Args: query [top_k] [repo]
kc_query() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf -X POST "$KNOWLEDGE_URL/query" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg q "$1" --argjson top_k "${2:-5}" --arg repo "${3:-}" \
        '{query:$q, top_k:$top_k, repo:(if $repo == "" then null else $repo end)}')"
  else
    # Sem equivalente local para busca semântica de repos
    echo "[]"
  fi
}

# Verifica saúde do serviço
kc_health() {
  if [ "$KC_MODE" = "remote" ]; then
    curl -sf "$KNOWLEDGE_URL/health" | jq -r '.status' 2>/dev/null
  else
    echo "ok (local/sqlite)"
  fi
}

# Retorna o modo atual (remote ou local)
kc_mode() {
  echo "$KC_MODE"
}
