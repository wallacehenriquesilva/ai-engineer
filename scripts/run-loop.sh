#!/bin/bash
# run-loop.sh — Executa /run em loop com contexto limpo a cada iteração
# Cada task roda numa sessão isolada do Claude Code.
#
# Uso:
#   ./scripts/run-loop.sh                  # intervalo padrão: 5 min
#   ./scripts/run-loop.sh --interval 10    # intervalo de 10 min
#   ./scripts/run-loop.sh --max 5          # máximo 5 tasks
#   ./scripts/run-loop.sh --command engineer  # roda /engineer em vez de /run
#   ./scripts/run-loop.sh --timeout 20     # timeout por execução em minutos (padrão: 15)

set -eo pipefail

INTERVAL=300
MAX_TASKS=0
COMMAND="/run"
WORK_DIR="${WORK_DIR:-$(pwd)}"
TIMEOUT_SECS=900  # 15 min por execução

while [ $# -gt 0 ]; do
  case $1 in
    --interval) INTERVAL=$(( $2 * 60 )); shift 2 ;;
    --max)      MAX_TASKS="$2";          shift 2 ;;
    --command)  COMMAND="/$2";           shift 2 ;;
    --dir)      WORK_DIR="$2";           shift 2 ;;
    --timeout)  TIMEOUT_SECS=$(( $2 * 60 )); shift 2 ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

echo ""
echo -e "${CYAN}AI Engineer — Loop Contínuo${NC}"
echo -e "${CYAN}═══════════════════════════${NC}"
echo ""
echo -e "  Comando:   ${CYAN}$COMMAND${NC}"
echo -e "  Intervalo: ${CYAN}$((INTERVAL / 60)) min${NC}"
echo -e "  Timeout:   ${CYAN}$((TIMEOUT_SECS / 60)) min/execução${NC}"
echo -e "  Máximo:    ${CYAN}$([ "$MAX_TASKS" -gt 0 ] && echo "$MAX_TASKS tasks" || echo "infinito")${NC}"
echo -e "  Diretório: ${CYAN}$WORK_DIR${NC}"
echo ""
echo -e "  ${YELLOW}Ctrl+C para parar${NC}"
echo ""

TASK_COUNT=0

while true; do
  TASK_COUNT=$((TASK_COUNT + 1))

  if [ "$MAX_TASKS" -gt 0 ] && [ "$TASK_COUNT" -gt "$MAX_TASKS" ]; then
    echo -e "\n${GREEN}Limite de $MAX_TASKS tasks atingido. Encerrando.${NC}"
    break
  fi

  echo -e "${CYAN}[$(date +%H:%M:%S)] Execução #$TASK_COUNT${NC}"

  cd "$WORK_DIR"
  timeout "$TIMEOUT_SECS" claude --print "$COMMAND" 2>&1 || true

  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 124 ]; then
    echo -e "${RED}[$(date +%H:%M:%S)] Execução #$TASK_COUNT: TIMEOUT após $((TIMEOUT_SECS / 60))min — run travada, continuando${NC}"
  elif [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}[$(date +%H:%M:%S)] Execução #$TASK_COUNT falhou (exit: $EXIT_CODE)${NC}"
  else
    echo -e "${GREEN}[$(date +%H:%M:%S)] Execução #$TASK_COUNT concluída${NC}"
  fi

  if [ "$MAX_TASKS" -gt 0 ] && [ "$TASK_COUNT" -ge "$MAX_TASKS" ]; then
    echo -e "\n${GREEN}Limite de $MAX_TASKS tasks atingido. Encerrando.${NC}"
    break
  fi

  echo -e "${YELLOW}[$(date +%H:%M:%S)] Aguardando $((INTERVAL / 60)) min...${NC}"
  sleep "$INTERVAL"
done

echo ""
echo -e "${CYAN}Total de execuções: $TASK_COUNT${NC}"
echo ""
