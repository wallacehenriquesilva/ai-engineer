#!/bin/bash
# execution-log.sh — Registra e consulta execuções do AI Engineer
#
# Modo primário: POST/GET no knowledge-service centralizado (compartilhado entre agentes).
# Fallback: JSON local em ~/.ai-engineer/executions/ (se o serviço estiver indisponível).
#
# Uso:
#   source scripts/execution-log.sh
#   exec_log_start "engineer" "AZUL-1234" "martech-integration-worker"
#   exec_log_end "PR aberta: https://..." "https://github.com/..." "$COST"
#   exec_log_fail 8 "SonarQube timeout após 2 tentativas"
#   exec_log_history [--limit 20] [--status success|failure] [--command engineer]
#   exec_log_stats [30]

KNOWLEDGE_URL="${KNOWLEDGE_SERVICE_URL:-http://localhost:8080}"
AGENT_ID="${AGENT_ID:-$(hostname)}"
EXEC_LOG_DIR="${EXEC_LOG_DIR:-$HOME/.ai-engineer/executions}"
mkdir -p "$EXEC_LOG_DIR"

_exec_service_available() {
  curl -sf "$KNOWLEDGE_URL/health" >/dev/null 2>&1
}

# ── Iniciar execução ─────────────────────────────────────────────────────────

exec_log_start() {
  local command="$1"    # engineer | pr-resolve | finalize | run
  local task_id="$2"    # AZUL-1234
  local repo="$3"       # nome do repo

  EXEC_START=$(date +%s)

  if _exec_service_available; then
    local response
    response=$(curl -sf -X POST "$KNOWLEDGE_URL/executions" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg cmd     "$command" \
        --arg task    "${task_id:-}" \
        --arg repo    "${repo:-}" \
        --arg agent   "$AGENT_ID" \
        '{command:$cmd, task:$task, repo:$repo, agent_id:$agent}')" 2>/dev/null)

    if [ -n "$response" ]; then
      EXEC_ID=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
      if [ -n "$EXEC_ID" ]; then
        EXEC_MODE="remote"
        EXEC_FILE=""
        export EXEC_ID EXEC_START EXEC_MODE EXEC_FILE
        echo "$EXEC_ID"
        return
      fi
    fi
  fi

  # Fallback local
  EXEC_ID="$(date +%Y%m%d_%H%M%S)_${command}_${task_id:-unknown}"
  EXEC_FILE="$EXEC_LOG_DIR/$EXEC_ID.json"
  EXEC_MODE="local"

  jq -n \
    --arg id       "$EXEC_ID" \
    --arg command  "$command" \
    --arg task     "${task_id:-}" \
    --arg repo     "${repo:-}" \
    --arg agent    "$AGENT_ID" \
    --arg start    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      id: $id, command: $command, task: $task, repo: $repo, agent_id: $agent,
      started_at: $start, finished_at: null, duration_seconds: 0,
      status: "running", result: null, failed_step: null, failure_reason: null,
      cost_usd: null, pr_url: null,
      tokens: {input: 0, cache_write: 0, cache_read: 0, output: 0}
    }' > "$EXEC_FILE"

  export EXEC_ID EXEC_START EXEC_MODE EXEC_FILE
  echo "$EXEC_ID"
}

# ── Finalizar com sucesso ────────────────────────────────────────────────────

exec_log_end() {
  local result="${1:-}"
  local pr_url="${2:-}"
  local cost="${3:-0}"
  local input="${4:-0}"
  local cache_write="${5:-0}"
  local cache_read="${6:-0}"
  local output="${7:-0}"

  [ -z "${EXEC_ID:-}" ] && return 1

  if [ "${EXEC_MODE:-}" = "remote" ]; then
    curl -sf -X PUT "$KNOWLEDGE_URL/executions/$EXEC_ID" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg status "success" --arg result "$result" \
        --arg pr_url "$pr_url" --argjson cost "$cost" \
        --argjson input "$input" --argjson cw "$cache_write" \
        --argjson cr "$cache_read" --argjson out "$output" \
        '{status:$status, result:$result, pr_url:$pr_url, cost_usd:$cost,
          tokens:{input:$input, cache_write:$cw, cache_read:$cr, output:$out}}')" \
      >/dev/null 2>&1
    return
  fi

  # Fallback local
  [ -z "${EXEC_FILE:-}" ] || [ ! -f "${EXEC_FILE:-}" ] && return 1

  local now=$(date +%s)
  local duration=$((now - EXEC_START))
  local tmp=$(mktemp)

  jq \
    --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson dur  "$duration" \
    --arg status   "success" \
    --arg result   "$result" \
    --arg pr_url   "$pr_url" \
    --arg cost     "$cost" \
    --arg input    "$input" \
    --arg cw       "$cache_write" \
    --arg cr       "$cache_read" \
    --arg out      "$output" \
    '.finished_at = $finished | .duration_seconds = $dur | .status = $status |
     .result = $result |
     .pr_url = (if $pr_url == "" then null else $pr_url end) |
     .cost_usd = ($cost | tonumber) |
     .tokens = {input: ($input|tonumber), cache_write: ($cw|tonumber),
                cache_read: ($cr|tonumber), output: ($out|tonumber)}' \
    "$EXEC_FILE" > "$tmp" && mv "$tmp" "$EXEC_FILE"
}

# ── Finalizar com falha ──────────────────────────────────────────────────────

exec_log_fail() {
  local step="${1:-0}"
  local reason="${2:-}"
  local pr_url="${3:-}"

  [ -z "${EXEC_ID:-}" ] && return 1

  if [ "${EXEC_MODE:-}" = "remote" ]; then
    curl -sf -X PUT "$KNOWLEDGE_URL/executions/$EXEC_ID" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg status "failure" --argjson step "$step" \
        --arg reason "$reason" --arg pr_url "$pr_url" \
        '{status:$status, failed_step:$step, failure_reason:$reason,
          pr_url:(if $pr_url == "" then null else $pr_url end)}')" \
      >/dev/null 2>&1
    return
  fi

  # Fallback local
  [ -z "${EXEC_FILE:-}" ] || [ ! -f "${EXEC_FILE:-}" ] && return 1

  local now=$(date +%s)
  local duration=$((now - EXEC_START))
  local tmp=$(mktemp)

  jq \
    --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson dur  "$duration" \
    --arg status   "failure" \
    --argjson step "$step" \
    --arg reason   "$reason" \
    --arg pr_url   "$pr_url" \
    '.finished_at = $finished | .duration_seconds = $dur | .status = $status |
     .failed_step = $step | .failure_reason = $reason |
     .pr_url = (if $pr_url == "" then null else $pr_url end)' \
    "$EXEC_FILE" > "$tmp" && mv "$tmp" "$EXEC_FILE"
}

# ── Histórico de execuções ───────────────────────────────────────────────────

exec_log_history() {
  local limit=20
  local status_filter=""
  local command_filter=""

  while [ $# -gt 0 ]; do
    case $1 in
      --limit)   limit="$2";          shift 2 ;;
      --status)  status_filter="$2";  shift 2 ;;
      --command) command_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if _exec_service_available; then
    local params="limit=$limit"
    [ -n "$status_filter" ]  && params="$params&status=$status_filter"
    [ -n "$command_filter" ] && params="$params&command=$command_filter"
    curl -sf "$KNOWLEDGE_URL/executions?$params"
    return
  fi

  # Fallback local
  local files
  files=$(ls -t "$EXEC_LOG_DIR"/*.json 2>/dev/null | head -"$limit")
  [ -z "$files" ] && echo "[]" && return 0

  echo "$files" | while read -r f; do
    local entry
    entry=$(cat "$f")
    if [ -n "$status_filter" ]; then
      echo "$entry" | jq -e --arg s "$status_filter" '.status == $s' >/dev/null 2>&1 || continue
    fi
    if [ -n "$command_filter" ]; then
      echo "$entry" | jq -e --arg c "$command_filter" '.command == $c' >/dev/null 2>&1 || continue
    fi
    echo "$entry"
  done | jq -s '.'
}

# ── Estatísticas ─────────────────────────────────────────────────────────────

exec_log_stats() {
  local days="${1:-30}"

  if _exec_service_available; then
    curl -sf "$KNOWLEDGE_URL/executions/stats?days=$days"
    return
  fi

  # Fallback local
  local cutoff
  cutoff=$(date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || echo "2000-01-01T00:00:00Z")

  local all
  all=$(cat "$EXEC_LOG_DIR"/*.json 2>/dev/null | jq -s --arg cutoff "$cutoff" '
    [.[] | select(.started_at >= $cutoff)]')

  [ "$all" = "[]" ] || [ -z "$all" ] && echo '{"total":0}' && return 0

  echo "$all" | jq '{
    total: length,
    success: [.[] | select(.status == "success")] | length,
    failure: [.[] | select(.status == "failure")] | length,
    running: [.[] | select(.status == "running")] | length,
    success_rate: (([.[] | select(.status == "success")] | length) / length * 100 | round),
    avg_duration_min: ([.[] | select(.duration_seconds > 0) | .duration_seconds] | if length > 0 then (add / length / 60 | round) else 0 end),
    total_cost_usd: ([.[] | .cost_usd // 0] | add | . * 10000 | round / 10000)
  }'
}
