---
name: history
version: 1.0.0
description: >
  Exibe o histórico de execuções do AI Engineer com estatísticas de sucesso,
  falhas, custos e duração. Uso: /history [--limit 20] [--status success|failure]
  [--command engineer|pr-resolve|finalize] [--stats] [--days 30]
depends-on: []
triggers:
  - user-command: /history
allowed-tools:
  - Bash
  - Read
---

# history: Histórico de Execuções

Exibe o histórico e estatísticas das execuções do AI Engineer.

---

## Etapa 1 — Verificar Diretório de Logs

```bash
EXEC_DIR="$HOME/.ai-engineer/executions"
ls "$EXEC_DIR"/*.json 2>/dev/null | wc -l | tr -d ' '
```

Se zero: **"Nenhuma execução registrada ainda. Execute /engineer ou /run para começar."**

---

## Etapa 2 — Detectar Modo

Analise a mensagem do usuário:

- `--stats` ou "estatísticas" → Seção A (Estatísticas)
- Qualquer outro caso → Seção B (Histórico)

---

## Seção A — Estatísticas

```bash
source ~/.ai-engineer/scripts/execution-log.sh
exec_log_stats ${DAYS:-30}
```

Apresente formatado:

```
## Estatísticas dos últimos <N> dias

| Métrica                | Valor          |
|------------------------|----------------|
| Total de execuções     | <total>        |
| Sucesso                | <n> (<rate>%)  |
| Falha                  | <n>            |
| Em andamento           | <n>            |
| Duração média          | <n> min        |
| Custo total            | $<cost>        |

### Por comando
<tabela command → total / sucesso>

### Top falhas
<lista das razões de falha mais comuns>
```

---

## Seção B — Histórico

```bash
source ~/.ai-engineer/scripts/execution-log.sh
exec_log_history --limit ${LIMIT:-20} ${STATUS:+--status $STATUS} ${COMMAND:+--command $COMMAND}
```

Apresente cada execução:

```
## Histórico de Execuções

| # | Data       | Comando   | Task       | Repo                | Status | Duração | Custo  |
|---|------------|-----------|------------|---------------------|--------|---------|--------|
| 1 | 2026-03-29 | engineer  | AZUL-1234  | martech-worker      | ✅     | 12 min  | $0.45  |
| 2 | 2026-03-28 | run       | AZUL-1200  | notification-hub    | ❌     | 8 min   | $0.32  |
```

Para execuções com falha, inclua o motivo:
```
> ❌ #2: Falha na Etapa 9 — SonarQube timeout após 2 tentativas
```

---

## Regras

- Sempre use o script `execution-log.sh` como fonte de dados.
- Ordene por data decrescente (mais recente primeiro).
- Formate custos com 4 casas decimais.
- Formate durações em minutos.
