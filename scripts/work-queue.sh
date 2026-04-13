#!/bin/bash
# work-queue.sh — Work queue baseado em SQLite para gerenciar tasks em paralelo
#
# Suporta múltiplas PRs por task (ex: multi-repo, app + infra).
# Uma task só é considerada concluída quando TODAS as suas PRs estão finalizadas.
#
# Uso:
#   source scripts/work-queue.sh
#   wq_init
#   wq_add "AZUL-1234" "my-service" "AZUL-1234/feat" "/path/worktree"
#   wq_set_pr "AZUL-1234" "my-service" "https://github.com/..."
#   wq_update_pr "AZUL-1234" "my-service" "has_feedback"
#   wq_list "waiting_review"
#   wq_next_action
#   wq_poll_prs

WQ_DB="${WQ_DB:-$HOME/.ai-engineer/queue.db}"

# ── Inicializar banco ───────────────────────────────────────────────────────

wq_init() {
  mkdir -p "$(dirname "$WQ_DB")"
  sqlite3 "$WQ_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS work_items (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id         TEXT NOT NULL,
  repo            TEXT NOT NULL,
  pr_url          TEXT,
  branch          TEXT,
  worktree_path   TEXT,
  status          TEXT NOT NULL DEFAULT 'implementing',
  priority        INTEGER NOT NULL DEFAULT 0,
  feedback_count  INTEGER NOT NULL DEFAULT 0,
  slack_thread_ts TEXT,
  created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  metadata        TEXT DEFAULT '{}',
  UNIQUE(task_id, repo)
);

CREATE TABLE IF NOT EXISTS work_queue_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id    TEXT NOT NULL,
  repo       TEXT,
  from_status TEXT,
  to_status  TEXT NOT NULL,
  reason     TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
SQL

  # Migração: se existir tabela antiga work_queue, migrar dados
  local has_old
  has_old=$(sqlite3 "$WQ_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='work_queue';" 2>/dev/null)
  if [ -n "$has_old" ]; then
    sqlite3 "$WQ_DB" <<'SQL'
INSERT OR IGNORE INTO work_items (task_id, repo, pr_url, branch, worktree_path, status, priority, feedback_count, created_at, updated_at, metadata)
SELECT task_id, repo, pr_url, branch, worktree_path, status, priority, feedback_count, created_at, updated_at, metadata
FROM work_queue;

DROP TABLE work_queue;
SQL
  fi

  # Migração: adicionar coluna repo ao work_queue_log se não existir
  local has_repo_col
  has_repo_col=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM pragma_table_info('work_queue_log') WHERE name='repo';" 2>/dev/null)
  if [ "$has_repo_col" = "0" ]; then
    sqlite3 "$WQ_DB" "ALTER TABLE work_queue_log ADD COLUMN repo TEXT;" 2>/dev/null || true
  fi

  # Migração: adicionar coluna slack_thread_ts ao work_items se não existir
  local has_slack_col
  has_slack_col=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM pragma_table_info('work_items') WHERE name='slack_thread_ts';" 2>/dev/null)
  if [ "$has_slack_col" = "0" ]; then
    sqlite3 "$WQ_DB" "ALTER TABLE work_items ADD COLUMN slack_thread_ts TEXT;" 2>/dev/null || true
  fi
}

# ── Adicionar item ao queue (uma PR por repo) ───────────────────────────────

wq_add() {
  local task_id="$1"
  local repo="$2"
  local branch="${3:-}"
  local worktree="${4:-}"
  local metadata="${5:-{}}"

  sqlite3 "$WQ_DB" <<SQL
INSERT OR REPLACE INTO work_items (task_id, repo, branch, worktree_path, status, metadata, updated_at)
VALUES ('$task_id', '$repo', '$branch', '$worktree', 'implementing', '$metadata', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
SQL

  _wq_log "$task_id" "$repo" "" "implementing" "Item adicionado ao queue"
}

# ── Atualizar status de um item (task + repo) ───────────────────────────────

wq_update_pr() {
  local task_id="$1"
  local repo="$2"
  local new_status="$3"
  local reason="${4:-}"

  local old_status
  old_status=$(sqlite3 "$WQ_DB" "SELECT status FROM work_items WHERE task_id='$task_id' AND repo='$repo';")

  local extra_sql=""
  if [ "$new_status" = "has_feedback" ]; then
    extra_sql=", feedback_count = feedback_count + 1"
  fi

  sqlite3 "$WQ_DB" <<SQL
UPDATE work_items
SET status = '$new_status', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') $extra_sql
WHERE task_id = '$task_id' AND repo = '$repo';
SQL

  _wq_log "$task_id" "$repo" "$old_status" "$new_status" "$reason"
}

# Atalho: atualizar por task_id (quando só tem 1 repo, ou atualizar todos)
wq_update() {
  local task_id="$1"
  local new_status="$2"
  local reason="${3:-}"

  local repos
  repos=$(sqlite3 "$WQ_DB" "SELECT repo FROM work_items WHERE task_id='$task_id';")
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    wq_update_pr "$task_id" "$repo" "$new_status" "$reason"
  done <<< "$repos"
}

# ── Atualizar PR URL (após abrir a PR) ─────────────────────────────────────

wq_set_pr() {
  local task_id="$1"
  local repo="$2"
  local pr_url="$3"

  sqlite3 "$WQ_DB" <<SQL
UPDATE work_items
SET pr_url = '$pr_url', status = 'waiting_review', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE task_id = '$task_id' AND repo = '$repo';
SQL

  _wq_log "$task_id" "$repo" "implementing" "waiting_review" "PR aberta: $pr_url"
}

# ── Slack thread ────────────────────────────────────────────────────────────

wq_set_slack_ts() {
  local task_id="$1"
  local repo="$2"
  local ts="$3"

  sqlite3 "$WQ_DB" <<SQL
UPDATE work_items
SET slack_thread_ts = '$ts', updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE task_id = '$task_id' AND repo = '$repo';
SQL
}

wq_get_slack_ts() {
  local task_id="$1"
  local repo="$2"

  sqlite3 "$WQ_DB" "SELECT slack_thread_ts FROM work_items WHERE task_id='$task_id' AND repo='$repo';" 2>/dev/null
}

# ── Buscar items por task ───────────────────────────────────────────────────

wq_get() {
  local task_id="$1"
  sqlite3 -json "$WQ_DB" "SELECT * FROM work_items WHERE task_id='$task_id';"
}

wq_get_pr() {
  local task_id="$1"
  local repo="$2"
  sqlite3 -json "$WQ_DB" "SELECT * FROM work_items WHERE task_id='$task_id' AND repo='$repo';" | jq '.[0] // empty'
}

# ── Listar items por status ─────────────────────────────────────────────────

wq_list() {
  local filter_status="${1:-}"

  if [ -n "$filter_status" ]; then
    sqlite3 -json "$WQ_DB" "SELECT * FROM work_items WHERE status='$filter_status' ORDER BY priority DESC, updated_at ASC;"
  else
    sqlite3 -json "$WQ_DB" "SELECT * FROM work_items WHERE status NOT IN ('done', 'failed') ORDER BY priority DESC, updated_at ASC;"
  fi
}

# ── Contar items ativos ─────────────────────────────────────────────────────

wq_count_active() {
  sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status NOT IN ('done', 'failed');"
}

# ── Contar PRs distintas aguardando review ──────────────────────────────────

wq_count_waiting() {
  sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='waiting_review';"
}

# ── Marcar item como done ───────────────────────────────────────────────────

wq_done_pr() {
  local task_id="$1"
  local repo="$2"
  wq_update_pr "$task_id" "$repo" "done" "PR concluída"
}

wq_fail_pr() {
  local task_id="$1"
  local repo="$2"
  local reason="${3:-}"
  wq_update_pr "$task_id" "$repo" "failed" "$reason"
}

# ── Verificar se TODAS as PRs de uma task estão done ────────────────────────

wq_is_task_done() {
  local task_id="$1"
  local total pending
  total=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE task_id='$task_id';")
  pending=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE task_id='$task_id' AND status NOT IN ('done', 'failed');")

  if [ "$total" -gt 0 ] && [ "$pending" -eq 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# ── Listar tasks com status agregado ────────────────────────────────────────

wq_task_summary() {
  local task_id="$1"
  sqlite3 -json "$WQ_DB" <<SQL
SELECT
  task_id,
  COUNT(*) as total_prs,
  SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as done_prs,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_prs,
  SUM(CASE WHEN status = 'waiting_review' THEN 1 ELSE 0 END) as waiting_prs,
  SUM(CASE WHEN status = 'has_feedback' THEN 1 ELSE 0 END) as feedback_prs,
  SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) as approved_prs,
  SUM(CASE WHEN status = 'implementing' THEN 1 ELSE 0 END) as implementing_prs,
  GROUP_CONCAT(repo || ':' || status, ', ') as details
FROM work_items
WHERE task_id = '$task_id'
GROUP BY task_id;
SQL
}

# ── Próxima ação a tomar ────────────────────────────────────────────────────
# Retorna JSON com a ação prioritária:
#   action: resolve | finalize | implement
#   task_id: AZUL-1234
#   repo: my-service
#   pr_url: https://...

wq_next_action() {
  # Prioridade 1: PRs com feedback (resolver comentários)
  local feedback
  feedback=$(sqlite3 -json "$WQ_DB" \
    "SELECT * FROM work_items WHERE status='has_feedback' ORDER BY priority DESC, updated_at ASC LIMIT 1;" \
    | jq '.[0] // empty')

  if [ -n "$feedback" ] && [ "$feedback" != "null" ]; then
    echo "$feedback" | jq '{action: "resolve", task_id: .task_id, repo: .repo, pr_url: .pr_url, worktree_path: .worktree_path}'
    return 0
  fi

  # Prioridade 2: PRs aprovadas (finalizar)
  local approved
  approved=$(sqlite3 -json "$WQ_DB" \
    "SELECT * FROM work_items WHERE status='approved' ORDER BY priority DESC, updated_at ASC LIMIT 1;" \
    | jq '.[0] // empty')

  if [ -n "$approved" ] && [ "$approved" != "null" ]; then
    echo "$approved" | jq '{action: "finalize", task_id: .task_id, repo: .repo, pr_url: .pr_url, worktree_path: .worktree_path}'
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
    "SELECT task_id, repo, pr_url FROM work_items WHERE status IN ('waiting_review') AND pr_url != '' AND pr_url IS NOT NULL;")

  [ -z "$prs" ] || [ "$prs" = "[]" ] && return 0

  echo "$prs" | jq -c '.[]' | while IFS= read -r row; do
    local task_id repo pr_url
    task_id=$(echo "$row" | jq -r '.task_id')
    repo=$(echo "$row" | jq -r '.repo')
    pr_url=$(echo "$row" | jq -r '.pr_url')

    # Buscar estado da PR
    local state
    state=$(gh pr view "$pr_url" --json state --jq '.state' 2>/dev/null)
    [ -z "$state" ] && continue

    # PR mergeada ou fechada
    if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
      wq_done_pr "$task_id" "$repo"
      continue
    fi

    # Verificar reviews
    local last_review
    last_review=$(gh pr view "$pr_url" --json reviews \
      --jq '[.reviews[] | select(.state != "COMMENTED")] | last | .state // empty' 2>/dev/null)

    if [ "$last_review" = "APPROVED" ]; then
      wq_update_pr "$task_id" "$repo" "approved" "PR aprovada"
      continue
    fi

    if [ "$last_review" = "CHANGES_REQUESTED" ]; then
      wq_update_pr "$task_id" "$repo" "has_feedback" "Changes requested"
      continue
    fi

    # Extrair pr_number e repo_full (necessarios para GraphQL)
    local pr_number repo_full
    pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
    repo_full=$(echo "$pr_url" | grep -oE '[^/]+/[^/]+/pull' | sed 's|/pull||')

    # Verificar review threads nao resolvidas via GraphQL
    # Nao filtra por data — verifica estado atual das threads
    local unresolved_threads="0"
    if [ -n "$pr_number" ] && [ -n "$repo_full" ]; then
      local owner repo_name
      owner=$(echo "$repo_full" | cut -d'/' -f1)
      repo_name=$(echo "$repo_full" | cut -d'/' -f2)

      unresolved_threads=$(gh api graphql -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                nodes {
                  isResolved
                }
              }
            }
          }
        }' -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null || echo "0")
    fi

    if [ "${unresolved_threads:-0}" -gt 0 ] 2>/dev/null; then
      wq_update_pr "$task_id" "$repo" "has_feedback" "$unresolved_threads threads nao resolvidas"
      continue
    fi

    # Verificar comentarios simples (issue comments) de qualquer pessoa
    local simple_comments
    simple_comments=$(gh pr view "$pr_url" --json comments \
      --jq "[.comments[] | select(.author.login != \"github-actions\")] | length" 2>/dev/null || echo "0")

    if [ "${simple_comments:-0}" -gt 0 ] 2>/dev/null; then
      wq_update_pr "$task_id" "$repo" "has_feedback" "$simple_comments comentarios simples"
      continue
    fi

    # Verificar CI checks falhando (sem comentários novos, mas checks vermelhos)
    local failed_checks
    failed_checks=$(gh pr checks "$pr_url" --json name,state \
      --jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")] | length' 2>/dev/null || echo "0")

    if [ "${failed_checks:-0}" -gt 0 ] 2>/dev/null; then
      local failed_names
      failed_names=$(gh pr checks "$pr_url" --json name,state \
        --jq '[.[] | select(.state == "FAILURE" or .state == "ERROR") | .name] | join(", ")' 2>/dev/null || echo "unknown")
      wq_update_pr "$task_id" "$repo" "has_feedback" "CI checks falhando: $failed_names"
    fi
  done
}

# ── Resumo do queue ─────────────────────────────────────────────────────────

wq_summary() {
  sqlite3 "$WQ_DB" <<'SQL'
SELECT
  status,
  COUNT(*) as count
FROM work_items
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
  total=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items;")
  implementing=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='implementing';")
  waiting=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='waiting_review';")
  feedback=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='has_feedback';")
  approved=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='approved';")
  done=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='done';")
  failed=$(sqlite3 "$WQ_DB" "SELECT COUNT(*) FROM work_items WHERE status='failed';")

  local distinct_tasks
  distinct_tasks=$(sqlite3 "$WQ_DB" "SELECT COUNT(DISTINCT task_id) FROM work_items;")
  local tasks_done
  tasks_done=$(sqlite3 "$WQ_DB" "
    SELECT COUNT(*) FROM (
      SELECT task_id FROM work_items
      GROUP BY task_id
      HAVING SUM(CASE WHEN status NOT IN ('done','failed') THEN 1 ELSE 0 END) = 0
    );")

  jq -n \
    --argjson total "$total" \
    --argjson implementing "$implementing" \
    --argjson waiting "$waiting" \
    --argjson feedback "$feedback" \
    --argjson approved "$approved" \
    --argjson done "$done" \
    --argjson failed "$failed" \
    --argjson tasks "$distinct_tasks" \
    --argjson tasks_done "$tasks_done" \
    '{total_items: $total, implementing: $implementing, waiting_review: $waiting,
      has_feedback: $feedback, approved: $approved, done: $done, failed: $failed,
      distinct_tasks: $tasks, tasks_fully_done: $tasks_done}'
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
DELETE FROM work_items
WHERE status IN ('done', 'failed')
AND updated_at < strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-$days days');

DELETE FROM work_queue_log
WHERE task_id NOT IN (SELECT task_id FROM work_items)
AND created_at < strftime('%Y-%m-%dT%H:%M:%SZ', 'now', '-$days days');
SQL
}

# ── Log interno ─────────────────────────────────────────────────────────────

_wq_log() {
  local task_id="$1" repo="$2" from_status="$3" to_status="$4" reason="$5"

  sqlite3 "$WQ_DB" <<SQL
INSERT INTO work_queue_log (task_id, repo, from_status, to_status, reason)
VALUES ('$task_id', '$repo', '$from_status', '$to_status', '$reason');
SQL
}
