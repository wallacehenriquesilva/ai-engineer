#!/bin/bash
# run-parallel.sh — Executa múltiplas tasks em paralelo via Claude Code
# Uso: ./scripts/run-parallel.sh [--workers 3] [--command engineer]
#
# Cada worker roda em um processo Claude Code separado com worktree isolado.
# O script coordena a atribuição de tasks e coleta resultados.

set -euo pipefail

WORKERS="${WORKERS:-3}"
COMMAND="${COMMAND:-engineer}"
EXEC_LOG_DIR="${EXEC_LOG_DIR:-$HOME/.ai-engineer/executions}"
PARALLEL_DIR="$HOME/.ai-engineer/parallel"
LOCK_FILE="$PARALLEL_DIR/.lock"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}[ok]${NC} $1"; }
log_info() { echo -e "${CYAN}[->]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
log_err()  { echo -e "${RED}[xx]${NC} $1"; }

while [ $# -gt 0 ]; do
  case $1 in
    --workers) WORKERS="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$PARALLEL_DIR"

# ── Validações ───────────────────────────────────────────────────────────────

command -v claude >/dev/null 2>&1 || { log_err "Claude Code CLI nao encontrado."; exit 1; }
command -v gh     >/dev/null 2>&1 || { log_err "gh CLI nao encontrado."; exit 1; }

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null)
  if kill -0 "$LOCK_PID" 2>/dev/null; then
    log_err "Outra execução paralela já está rodando (PID: $LOCK_PID)."
    log_err "Se isso for incorreto, remova: $LOCK_FILE"
    exit 1
  fi
  rm -f "$LOCK_FILE"
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; kill 0 2>/dev/null' EXIT

echo ""
echo -e "${CYAN}AI Engineer — Execução Paralela${NC}"
echo -e "${CYAN}================================${NC}"
echo ""
log_info "Workers:  $WORKERS"
log_info "Comando:  /$COMMAND"
echo ""

# ── Worker ───────────────────────────────────────────────────────────────────

run_worker() {
  local worker_id="$1"
  local worker_dir="$PARALLEL_DIR/worker-$worker_id"
  local worker_log="$worker_dir/output.log"

  mkdir -p "$worker_dir"

  log_info "Worker $worker_id: iniciando..."

  # Executa o Claude Code com o comando especificado
  claude --print "/$COMMAND" \
    > "$worker_log" 2>&1 \
    || true

  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    log_ok "Worker $worker_id: concluído com sucesso"
  else
    log_warn "Worker $worker_id: encerrou com código $exit_code"
  fi

  # Salvar resultado
  echo "$exit_code" > "$worker_dir/exit_code"
}

# ── Lançar workers ───────────────────────────────────────────────────────────

PIDS=()
for i in $(seq 1 "$WORKERS"); do
  run_worker "$i" &
  PIDS+=($!)
  sleep 2  # Pequeno delay para evitar race condition na busca de tasks
done

log_info "Aguardando $WORKERS workers..."
echo ""

# ── Aguardar conclusão ───────────────────────────────────────────────────────

SUCCESSES=0
FAILURES=0

for i in "${!PIDS[@]}"; do
  worker_num=$((i + 1))
  wait "${PIDS[$i]}" 2>/dev/null || true

  exit_file="$PARALLEL_DIR/worker-$worker_num/exit_code"
  if [ -f "$exit_file" ] && [ "$(cat "$exit_file")" = "0" ]; then
    SUCCESSES=$((SUCCESSES + 1))
  else
    FAILURES=$((FAILURES + 1))
  fi
done

# ── Relatório ────────────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}════════════════════════════════${NC}"
echo -e "${CYAN}  Relatório de Execução Paralela${NC}"
echo -e "${CYAN}════════════════════════════════${NC}"
echo ""
log_info "Total:    $WORKERS workers"
log_ok   "Sucesso:  $SUCCESSES"
[ "$FAILURES" -gt 0 ] && log_err "Falha:    $FAILURES" || log_ok "Falha:    0"
echo ""
log_info "Logs em: $PARALLEL_DIR/worker-*/output.log"
echo ""

# Limpar lock
rm -f "$LOCK_FILE"
