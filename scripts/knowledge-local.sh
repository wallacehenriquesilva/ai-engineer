#!/bin/bash
# knowledge-local.sh — Storage local de learnings e execuções via SQLite
#
# Fallback para quando o knowledge-service (PostgreSQL + pgvector) não está disponível.
# Mesma interface que o knowledge-client.sh, mas sem busca semântica.
#
# Uso: source scripts/knowledge-local.sh
#      kl_init
#      kl_learning_create "repo" "task" 9 "test_failure" "msg" "cause" "solution" "pattern"

KL_DB="${KL_DB:-$HOME/.ai-engineer/knowledge.db}"
AGENT_ID="${AGENT_ID:-$(hostname)}"

# ── Inicializar banco ───────────────────────────────────────────────────────

kl_init() {
  mkdir -p "$(dirname "$KL_DB")"
  sqlite3 "$KL_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS learnings (
  id             TEXT PRIMARY KEY,
  repo           TEXT NOT NULL,
  task           TEXT,
  step           INTEGER,
  error_type     TEXT NOT NULL,
  error_message  TEXT NOT NULL,
  root_cause     TEXT NOT NULL,
  solution       TEXT NOT NULL,
  pattern        TEXT NOT NULL UNIQUE,
  times_seen     INTEGER NOT NULL DEFAULT 1,
  resolved       INTEGER NOT NULL DEFAULT 0,
  promoted       INTEGER NOT NULL DEFAULT 0,
  agent_id       TEXT,
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE IF NOT EXISTS executions (
  id             TEXT PRIMARY KEY,
  command        TEXT NOT NULL,
  task           TEXT,
  repo           TEXT,
  agent_id       TEXT,
  status         TEXT NOT NULL DEFAULT 'running',
  result         TEXT,
  pr_url         TEXT,
  failed_step    INTEGER,
  failure_reason TEXT,
  cost_usd       REAL DEFAULT 0,
  tokens_input   INTEGER DEFAULT 0,
  tokens_cache_write INTEGER DEFAULT 0,
  tokens_cache_read  INTEGER DEFAULT 0,
  tokens_output  INTEGER DEFAULT 0,
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
SQL
}

# ── Gerar UUID simples ──────────────────────────────────────────────────────

_kl_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
      printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x' \
        $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
  fi
}

# ── Learnings ───────────────────────────────────────────────────────────────

# Registra um aprendizado (ou incrementa times_seen se pattern já existir)
# Args: repo, task, step, error_type, error_message, root_cause, solution, pattern
kl_learning_create() {
  local repo="$1" task="$2" step="${3:-0}" error_type="$4"
  local error_message="$5" root_cause="$6" solution="$7" pattern="$8"

  # Tenta incrementar se pattern já existe
  local existing
  existing=$(sqlite3 "$KL_DB" "UPDATE learnings SET times_seen = times_seen + 1, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE pattern = '$pattern' RETURNING id;" 2>/dev/null)

  if [ -n "$existing" ]; then
    # Pattern já existia, retorna o registro atualizado
    sqlite3 -json "$KL_DB" "SELECT * FROM learnings WHERE id = '$existing';" | jq '.[0] // empty'
    return 0
  fi

  # Insere novo learning
  local id
  id=$(_kl_uuid)
  sqlite3 "$KL_DB" <<SQL
INSERT INTO learnings (id, repo, task, step, error_type, error_message, root_cause, solution, pattern, agent_id)
VALUES ('$id', '$repo', '$task', $step, '$error_type', '$(echo "$error_message" | sed "s/'/''/g")', '$(echo "$root_cause" | sed "s/'/''/g")', '$(echo "$solution" | sed "s/'/''/g")', '$pattern', '$AGENT_ID');
SQL

  sqlite3 -json "$KL_DB" "SELECT * FROM learnings WHERE id = '$id';" | jq '.[0] // empty'
}

# Busca learnings por texto (fallback sem semântica — match por pattern, repo, solution)
# Args: query [repo] [top_k]
kl_learning_search() {
  local query="$1" repo="${2:-}" top_k="${3:-5}"
  local where="resolved = 0"

  [ -n "$repo" ] && where="$where AND repo = '$repo'"

  # Busca por LIKE em pattern, solution, error_message e root_cause
  sqlite3 -json "$KL_DB" <<SQL
SELECT *, 0.0 as score FROM learnings
WHERE $where AND (
  pattern LIKE '%$query%'
  OR solution LIKE '%$query%'
  OR error_message LIKE '%$query%'
  OR root_cause LIKE '%$query%'
)
ORDER BY times_seen DESC
LIMIT $top_k;
SQL
}

# Lista learnings filtrados por repo
# Args: [repo]
kl_learning_list() {
  local repo="${1:-}"
  if [ -n "$repo" ]; then
    sqlite3 -json "$KL_DB" "SELECT * FROM learnings WHERE repo = '$repo' AND resolved = 0 ORDER BY times_seen DESC;"
  else
    sqlite3 -json "$KL_DB" "SELECT * FROM learnings WHERE resolved = 0 ORDER BY times_seen DESC;"
  fi
}

# Lista learnings candidatos a promoção (times_seen >= threshold, não promovidos)
# Args: [threshold]
kl_learning_promotions() {
  local threshold="${1:-3}"
  sqlite3 -json "$KL_DB" "SELECT * FROM learnings WHERE times_seen >= $threshold AND promoted = 0 AND resolved = 0 ORDER BY times_seen DESC;"
}

# Marca learning como resolvido
# Args: learning_id
kl_learning_resolve() {
  sqlite3 "$KL_DB" "UPDATE learnings SET resolved = 1, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = '$1';"
}

# Marca learning como promovido
# Args: learning_id
kl_learning_promote() {
  sqlite3 "$KL_DB" "UPDATE learnings SET promoted = 1, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') WHERE id = '$1';"
}

# ── Executions ──────────────────────────────────────────────────────────────

# Inicia uma execução — retorna JSON com {id, status}
# Args: command, task, repo
kl_exec_start() {
  local id
  id=$(_kl_uuid)
  sqlite3 "$KL_DB" <<SQL
INSERT INTO executions (id, command, task, repo, agent_id)
VALUES ('$id', '$1', '${2:-}', '${3:-}', '$AGENT_ID');
SQL
  echo "{\"id\":\"$id\",\"status\":\"running\"}"
}

# Finaliza execução com sucesso
# Args: id, result, [pr_url], [cost], [input], [cache_write], [cache_read], [output]
kl_exec_end() {
  sqlite3 "$KL_DB" <<SQL
UPDATE executions SET
  status = 'success',
  result = '$(echo "${2:-}" | sed "s/'/''/g")',
  pr_url = '${3:-}',
  cost_usd = ${4:-0},
  tokens_input = ${5:-0},
  tokens_cache_write = ${6:-0},
  tokens_cache_read = ${7:-0},
  tokens_output = ${8:-0},
  updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE id = '$1';
SQL
}

# Finaliza execução com falha
# Args: id, step, reason, [pr_url]
kl_exec_fail() {
  sqlite3 "$KL_DB" <<SQL
UPDATE executions SET
  status = 'failure',
  failed_step = ${2:-0},
  failure_reason = '$(echo "${3:-}" | sed "s/'/''/g")',
  pr_url = '${4:-}',
  updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE id = '$1';
SQL
}

# Estatísticas agregadas
# Args: [days]
kl_exec_stats() {
  local days="${1:-30}"
  sqlite3 -json "$KL_DB" <<SQL
SELECT
  COUNT(*) as total,
  SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as success,
  SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) as failure,
  ROUND(AVG(cost_usd), 2) as avg_cost,
  ROUND(SUM(cost_usd), 2) as total_cost
FROM executions
WHERE created_at > strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-$days days');
SQL
}

# Lista execuções
# Args: [limit] [status] [command] [agent_id]
kl_exec_list() {
  local limit="${1:-20}"
  local where="1=1"
  [ -n "${2:-}" ] && where="$where AND status = '${2}'"
  [ -n "${3:-}" ] && where="$where AND command = '${3}'"
  [ -n "${4:-}" ] && where="$where AND agent_id = '${4}'"
  sqlite3 -json "$KL_DB" "SELECT * FROM executions WHERE $where ORDER BY created_at DESC LIMIT $limit;"
}
