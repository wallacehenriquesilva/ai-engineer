#!/bin/bash
# work-queue.sh — Work queue baseado em SQLite para gerenciar tasks em paralelo
#
# Permite ao agente implementar tasks sem bloquear esperando review.
# PRs são monitoradas em background e priorizadas quando recebem feedback.
#
# Uso:
#   source scripts/work-queue.sh
#   wq_init
#   wq_add "AZUL-1234" "https://github.com/..." "my-service" "AZUL-1234/feat" "/path/worktree"
#   wq_update "AZUL-1234" "has_feedback"
#   wq_list "waiting_review"
#   wq_next_action
#   wq_poll_prs

WQ_DB="${WQ_DB:-$HOME/.ai-engineer/queue.db}"

# ── Inicializar banco ───────────────────────────────────────────────────────

wq_init() {
  mkdir -p "$(dirname "$WQ_DB")"
  sqlite3 "$WQ_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS work_queue (
  task_id        TEXT PRIMARY KEY,
  pr_url         TEXT,
  repo           TEXT NOT NULL,
  branch         TEXT,
  worktree_path  TEXT,
  status         TEXT NOT NULL DEFAULT 'implementing',
  priority       INTEGER NOT NULL DEFAULT 0,
  feedback_count INTEGER NOT NULL DEFAULT 0,
  created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  metadata       TEXT DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS work_queue_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id    TEXT NOT NULL,
  from_status TEXT,
  to_status  TEXT NOT NULL,
  reason     TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
SQL
}

# ── Adicionar task ao queue ─────────────────────────────────────────────────

wq_add() {
  local task_id="$1"
  local pr_url="${2:-}"
  local repo="$3"
  local branch="${4:-}"
  local worktree="${5:-}"
  local metadata="${6:-{}}"

  sqlite3 "$WQ_DB" <<SQL
INSERT OR REPLACE INTO work_queue (task_id, pr_url, repo, branch, worktree_path, status, metadata, updated_at)
VALUES ('$task_id', '$pr_url', '$repo', '$branch', '$worktree', 'implementing', '$metadata', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
SQL

  _wq_log "$task_id" "" "implementing" "Task adicionada ao queue"
}

# ── Atualizar status ────────────────────────────────────────────────────────

wq_update() {
  local task_id="$1"
  local new_status="$2"
  local reason="${3:-}"

  local old_status
  old_status=$(sqlite3 "$WQ_DB" "SELECT status FROM work_queue WHERE task_id='$task_id';")

  local extra_sql=""
  if [ "$new_status" = "has_feedback" ]; then
    extra_sql=", feedback_count = feedback_count + 1"
  fi

  sqlite3 "$WQ_DB" <<SQL
UPDATE work_queue
SET status = '$new_status', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') $extra_sql
WHERE task_id = '$task_id';
SQL

  _wq_log "$task_id" "$old_status" "$new_status" "$reason"
}

# ── Atualizar PR URL (após abrir a PR) ─────────────────────────────────────

wq_set_pr() {
  local task_id="$1"
  local pr_url="$2"

  sqlite3 "$WQ_DB" <<SQL
UPDATE work_queue
SET pr_url = '$pr_url', status = 'waiting_review', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE task_id = '$task_id';
SQL

  _wq_log "$task_id" "implementing" "waiting_review" "PR aberta: $pr_url"
}

# ── Buscar task por ID ──────────────────────────────────────────────────────

wq_get() {
  local task_id="$1"
  sqlite3 -json "$WQ_DB" "SELECT * FROM work_queue WHERE task_id='$task_id';" | jq '.[0] // empty'
}

# ── Listar tasks por status ─────────────────────────────────────────────────

wq_list() {
  local status="${1:-}"

  if [ -n "$status" ]; then
    sqlite3 -json "$WQ_DB" "SELECT * FROM work_queue WHERE status='$status' ORDER BY priority DESC, updated_at ASC;"
  else
    sqlite3 -json "$WQ_DB" "SELECT * FROM work_queue WHERE status != 'done' AND status != 'failed' ORDER BY priority DESC, updated_at ASC;"
  fi
}

# ── Contar tasks ativas ─────────────────────────────────────────────────────

wq_count_active() {
  sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status NOT IN ('done', 'failed');"
}

# ── Remover task concluída ──────────────────────────────────────────────────

wq_done() {
  local task_id="$1"
  wq_update "$task_id" "done" "Task concluída"
}

wq_fail() {
  local task_id="$1"
  local reason="${2:-}"
  wq_update "$task_id" "failed" "$reason"
}

# ── Próxima ação a tomar ────────────────────────────────────────────────────
# Retorna JSON com a ação prioritária:
#   action: resolve | finalize | implement
#   task_id: AZUL-1234
#   pr_url: https://...

wq_next_action() {
  # Prioridade 1: PRs com feedback (resolver comentários)
  local feedback
  feedback=$(sqlite3 -json "$WQ_DB" \
    "SELECT * FROM work_queue WHERE status='has_feedback' ORDER BY priority DESC, updated_at ASC LIMIT 1;" \
    | jq '.[0] // empty')

  if [ -n "$feedback" ] && [ "$feedback" != "null" ]; then
    echo "$feedback" | jq '{action: "resolve", task_id: .task_id, pr_url: .pr_url, repo: .repo, worktree_path: .worktree_path}'
    return 0
  fi

  # Prioridade 2: PRs aprovadas (finalizar)
  local approved
  approved=$(sqlite3 -json "$WQ_DB" \
    "SELECT * FROM work_queue WHERE status='approved' ORDER BY priority DESC, updated_at ASC LIMIT 1;" \
    | jq '.[0] // empty')

  if [ -n "$approved" ] && [ "$approved" != "null" ]; then
    echo "$approved" | jq '{action: "finalize", task_id: .task_id, pr_url: .pr_url, repo: .repo, worktree_path: .worktree_path}'
    return 0
  fi

  # Prioridade 3: Nenhuma ação urgente — pode implementar nova task
  echo '{"action": "implement"}'
  return 0
}

# ── Poll de PRs — verifica status de todas as PRs pendentes ─────────────────

wq_poll_prs() {
  local prs
  prs=$(sqlite3 -json "$WQ_DB" \
    "SELECT task_id, pr_url FROM work_queue WHERE status IN ('waiting_review') AND pr_url != '' AND pr_url IS NOT NULL;")

  [ -z "$prs" ] || [ "$prs" = "[]" ] && return 0

  echo "$prs" | jq -c '.[]' | while IFS= read -r row; do
    local task_id pr_url
    task_id=$(echo "$row" | jq -r '.task_id')
    pr_url=$(echo "$row" | jq -r '.pr_url')

    # Buscar estado da PR
    local pr_data
    pr_data=$(gh pr view "$pr_url" --json state,reviews,comments 2>/dev/null)
    [ -z "$pr_data" ] && continue

    local state
    state=$(echo "$pr_data" | jq -r '.state')

    # PR mergeada ou fechada
    if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
      wq_update "$task_id" "done" "PR $state"
      continue
    fi

    # Verificar reviews
    local last_review
    last_review=$(echo "$pr_data" | jq -r '[.reviews[] | select(.state != "COMMENTED")] | last | .state // empty')

    if [ "$last_review" = "APPROVED" ]; then
      wq_update "$task_id" "approved" "PR aprovada"
      continue
    fi

    if [ "$last_review" = "CHANGES_REQUESTED" ]; then
      wq_update "$task_id" "has_feedback" "Changes requested"
      continue
    fi

    # Verificar comentários novos (excluindo bots)
    local sonar_bot="${SONAR_BOT:-sonarqube-v2-contaazul}"
    local new_comments
    new_comments=$(echo "$pr_data" | jq -r \
      --arg bot "$sonar_bot" \
      '[.comments[] | select(.author.login != $bot)] | length')

    if [ "$new_comments" -gt 0 ]; then
      # Verificar se há comentários mais recentes que o último update
      local last_updated
      last_updated=$(sqlite3 "$WQ_DB" "SELECT updated_at FROM work_queue WHERE task_id='$task_id';")

      local recent_comments
      recent_comments=$(echo "$pr_data" | jq -r \
        --arg bot "$sonar_bot" \
        --arg since "$last_updated" \
        '[.comments[] | select(.author.login != $bot and .createdAt > $since)] | length')

      if [ "$recent_comments" -gt 0 ]; then
        wq_update "$task_id" "has_feedback" "$recent_comments novos comentários"
      fi
    fi
  done
}

# ── Resumo do queue ─────────────────────────────────────────────────────────

wq_summary() {
  sqlite3 "$WQ_DB" <<'SQL'
SELECT
  status,
  COUNT(*) as count
FROM work_queue
WHERE status NOT IN ('done', 'failed')
GROUP BY status
ORDER BY
  CASE status
    WHEN 'has_feedback' THEN 1
    WHEN 'approved' THEN 2
    WHEN 'implementing' THEN 3
    WHEN 'waiting_review' THEN 4
    WHEN 'finalizing' THEN 5
  END;
SQL
}

wq_summary_json() {
  local total implementing waiting feedback approved done failed
  total=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue;")
  implementing=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status='implementing';")
  waiting=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status='waiting_review';")
  feedback=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status='has_feedback';")
  approved=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status='approved';")
  done=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status='done';")
  failed=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_queue WHERE status='failed';")

  jq -n \
    --argjson total "$total" \
    --argjson implementing "$implementing" \
    --argjson waiting "$waiting" \
    --argjson feedback "$feedback" \
    --argjson approved "$approved" \
    --argjson done "$done" \
    --argjson failed "$failed" \
    '{total: $total, implementing: $implementing, waiting_review: $waiting,
      has_feedback: $feedback, approved: $approved, done: $done, failed: $failed}'
}

# ── Histórico de transições ─────────────────────────────────────────────────

wq_history() {
  local task_id="${1:-}"

  if [ -n "$task_id" ]; then
    sqlite3 -json "$WQ_DB" \
      "SELECT * FROM work_queue_log WHERE task_id='$task_id' ORDER BY created_at ASC;"
  else
    sqlite3 -json "$WQ_DB" \
      "SELECT * FROM work_queue_log ORDER BY created_at DESC LIMIT 50;"
  fi
}

# ── Limpar tasks concluídas (mais de N dias) ────────────────────────────────

wq_cleanup() {
  local days="${1:-7}"

  sqlite3 "$WQ_DB" <<SQL
DELETE FROM work_queue
WHERE status IN ('done', 'failed')
AND updated_at < strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-$days days');

DELETE FROM work_queue_log
WHERE task_id NOT IN (SELECT task_id FROM work_queue)
AND created_at < strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-$days days');
SQL
}

# ── Log interno ─────────────────────────────────────────────────────────────

_wq_log() {
  local task_id="$1" from_status="$2" to_status="$3" reason="$4"

  sqlite3 "$WQ_DB" <<SQL
INSERT INTO work_queue_log (task_id, from_status, to_status, reason)
VALUES ('$task_id', '$from_status', '$to_status', '$reason');
SQL
}
