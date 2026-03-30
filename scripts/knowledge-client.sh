#!/bin/bash
# knowledge-client.sh — Cliente leve para o knowledge-service centralizado
# Uso: source scripts/knowledge-client.sh
#
# Todas as funções comunicam com o serviço remoto via HTTP.
# Cada agente se identifica pelo AGENT_ID (default: hostname).

KNOWLEDGE_URL="${KNOWLEDGE_SERVICE_URL:-http://localhost:8080}"
AGENT_ID="${AGENT_ID:-$(hostname)}"

# ── Learnings ────────────────────────────────────────────────────────────────

# Registra um aprendizado (ou incrementa times_seen se pattern já existir)
# Args: repo, task, step, error_type, error_message, root_cause, solution, pattern
kc_learning_create() {
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
}

# Busca semântica de learnings
# Args: query [repo] [top_k]
kc_learning_search() {
  curl -sf -X POST "$KNOWLEDGE_URL/learnings/search" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$1" --arg repo "${2:-}" --argjson top_k "${3:-5}" \
      '{query:$q, repo:(if $repo == "" then null else $repo end), top_k:$top_k, unresolved_only:true}')"
}

# Lista learnings filtrados por repo
# Args: [repo]
kc_learning_list() {
  local params=""
  [ -n "${1:-}" ] && params="?repo=$1&unresolved=true" || params="?unresolved=true"
  curl -sf "$KNOWLEDGE_URL/learnings$params"
}

# Lista learnings candidatos a promoção (times_seen >= 3)
kc_learning_promotions() {
  curl -sf "$KNOWLEDGE_URL/learnings/promotions"
}

# Marca learning como resolvido
# Args: learning_id
kc_learning_resolve() {
  curl -sf -X PUT "$KNOWLEDGE_URL/learnings/$1/resolve"
}

# ── Executions ───────────────────────────────────────────────────────────────

# Inicia uma execução — retorna JSON com {id, status}
# Args: command, task, repo
kc_exec_start() {
  curl -sf -X POST "$KNOWLEDGE_URL/executions" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg cmd "$1" --arg task "${2:-}" --arg repo "${3:-}" \
      --arg agent_id "$AGENT_ID" \
      '{command:$cmd, task:$task, repo:$repo, agent_id:$agent_id}')"
}

# Finaliza execução com sucesso
# Args: id, result, [pr_url], [cost], [input], [cache_write], [cache_read], [output]
kc_exec_end() {
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
}

# Finaliza execução com falha
# Args: id, step, reason, [pr_url]
kc_exec_fail() {
  curl -sf -X PUT "$KNOWLEDGE_URL/executions/$1" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg status "failure" --argjson step "${2:-0}" \
      --arg reason "${3:-}" --arg pr_url "${4:-}" \
      '{status:$status, failed_step:$step, failure_reason:$reason, pr_url:$pr_url}')"
}

# Estatísticas agregadas
# Args: [days]
kc_exec_stats() {
  curl -sf "$KNOWLEDGE_URL/executions/stats?days=${1:-30}"
}

# Lista execuções
# Args: [limit] [status] [command] [agent_id]
kc_exec_list() {
  local params="limit=${1:-20}"
  [ -n "${2:-}" ] && params="$params&status=$2"
  [ -n "${3:-}" ] && params="$params&command=$3"
  [ -n "${4:-}" ] && params="$params&agent_id=$4"
  curl -sf "$KNOWLEDGE_URL/executions?$params"
}

# ── Knowledge (wrappers) ────────────────────────────────────────────────────

# Busca semântica no knowledge base de repos
# Args: query [top_k] [repo]
kc_query() {
  curl -sf -X POST "$KNOWLEDGE_URL/query" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$1" --argjson top_k "${2:-5}" --arg repo "${3:-}" \
      '{query:$q, top_k:$top_k, repo:(if $repo == "" then null else $repo end)}')"
}

# Verifica saúde do serviço
kc_health() {
  curl -sf "$KNOWLEDGE_URL/health" | jq -r '.status' 2>/dev/null
}
