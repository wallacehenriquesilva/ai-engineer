# /run-queue

Execucao continua com work queue. Implementa tasks sem bloquear esperando review.

## REGRAS ABSOLUTAS

**LEIA ISTO ANTES DE QUALQUER ACAO:**

1. **Voce NAO busca tasks no Jira.** O @orchestrator faz isso.
2. **Voce NAO avalia clareza de tasks.** O @orchestrator faz isso utilizando o @task-fetcher para buscar as informações da task.
3. **Voce NAO le ou escreve codigo.** Os sub-agents fazem isso.
4. **Voce NAO resolve comentarios de PR.** O @pr-resolver faz isso.
5. **Voce NAO faz deploy.** O @finalizer faz isso.
6. **Voce NAO busca no backlog.** Se o orchestrator retornar no_task, aguarde e tente novamente.
7. **Voce APENAS:** inicializa o queue, roda o loop, spawna agents, le retornos JSON, atualiza o queue.

Se voce se perceber buscando tasks, lendo codigo, ou fazendo qualquer trabalho que deveria ser de um sub-agent — PARE. Spawne o agent correto.

---

## Flags

- `--max-tasks <N>` → Maximo de tasks a processar (padrao: 10)
- `--max-active <N>` → Maximo de PRs ativas simultaneamente (padrao: 5)

---

## Inicializar

### Parse de flags

Antes de qualquer coisa, parse os argumentos recebidos via `$ARGUMENTS`:

```bash
MAX_TASKS=10
MAX_ACTIVE=5

for arg in $ARGUMENTS; do
  case $arg in
    --max-tasks) shift; MAX_TASKS=$1 ;;
    --max-active) shift; MAX_ACTIVE=$1 ;;
  esac
done
```

### Configurações e queue

```bash
source ~/.ai-engineer/scripts/work-queue.sh
wq_init

BUDGET_LIMIT=$(grep "Budget limit:" CLAUDE.md | grep -oE '[0-9]+\.[0-9]+' || echo "5.00")
CIRCUIT_BREAKER_THRESHOLD=$(grep "Circuit breaker:" CLAUDE.md | grep -oE '[0-9]+' | head -1 || echo "3")
POLL_INTERVAL=60
TASKS_PROCESSED=0
CONSECUTIVE_FAILURES=0
```

**CRITICAL:** Use APENAS as funcoes listadas abaixo. NAO invente funcoes que nao existem.

| Funcao | Uso |
|---|---|
| `wq_init` | Inicializa banco SQLite |
| `wq_add <task_id> <repo> [branch] [worktree]` | Adiciona item ao queue |
| `wq_set_pr <task_id> <repo> <pr_url>` | Define PR URL, muda para waiting_review |
| `wq_update_pr <task_id> <repo> <status> [reason]` | Atualiza status de um item |
| `wq_get <task_id>` | Retorna items de uma task (JSON) |
| `wq_list [status]` | Lista items por status ou todos ativos (JSON) |
| `wq_count_active` | Conta items ativos |
| `wq_count_waiting` | Conta items em waiting_review |
| `wq_done_pr <task_id> <repo>` | Marca como done |
| `wq_fail_pr <task_id> <repo> [reason]` | Marca como failed |
| `wq_is_task_done <task_id>` | "true" se todas PRs da task estao done |
| `wq_next_action` | Retorna proxima acao (JSON: action, task_id, repo, pr_url) |
| `wq_poll_prs` | Verifica status de PRs via GitHub |
| `wq_summary` | Resumo por status (texto) |
| `wq_summary_json` | Resumo com contadores (JSON) |
| `wq_history [task_id]` | Log de transicoes |
| `wq_cleanup [days]` | Remove items antigos |
| `wq_set_slack_ts <task_id> <repo> <ts>` | Salva timestamp do Slack para reply na thread |
| `wq_get_slack_ts <task_id> <repo>` | Retorna timestamp do Slack (para responder na thread) |

Verifique estado anterior do queue (persiste entre sessoes):

```bash
ACTIVE=$(wq_count_active)
SUMMARY=$(wq_summary_json)
echo "$SUMMARY" | jq '.'
```

---

## Loop Principal

Repita ate `TASKS_PROCESSED >= MAX_TASKS` ou circuit breaker disparar:

### 0. Verificar circuit breaker

**No inicio de cada iteracao, antes de qualquer outra coisa:**

```bash
if [ "$CONSECUTIVE_FAILURES" -ge "$CIRCUIT_BREAKER_THRESHOLD" ]; then
  echo "Circuit breaker ativo ($CONSECUTIVE_FAILURES falhas consecutivas). Encerrando."
  break
fi
```

### 1. Poll PRs

```bash
wq_poll_prs
```

### 2. Proxima acao

```bash
NEXT=$(wq_next_action)
ACTION=$(echo "$NEXT" | jq -r '.action')
```

### 3. Executar

#### Se ACTION = resolve:

```bash
TASK_ID=$(echo "$NEXT" | jq -r '.task_id')
PR_URL=$(echo "$NEXT" | jq -r '.pr_url')
REPO=$(echo "$NEXT" | jq -r '.repo')
wq_update_pr "$TASK_ID" "$REPO" "implementing" "Resolvendo feedback"
```

**Spawne @pr-resolver** (NAO resolva voce mesmo):

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/pr-resolver.md.
           Flags: --no-poll
           PR: <PR_URL>
           Task: <TASK_ID>
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "opus"
)
```

Parse o JSON de retorno:
- `status: "resolved"` ou `"approved"` →
  ```bash
  wq_update_pr "$TASK_ID" "$REPO" "waiting_review" "Feedback resolvido"
  CONSECUTIVE_FAILURES=0
  ```
- Qualquer outro →
  ```bash
  wq_fail_pr "$TASK_ID" "$REPO" "<erro do JSON>"
  CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
  ```

#### Se ACTION = finalize:

```bash
TASK_ID=$(echo "$NEXT" | jq -r '.task_id')
PR_URL=$(echo "$NEXT" | jq -r '.pr_url')
REPO=$(echo "$NEXT" | jq -r '.repo')
wq_update_pr "$TASK_ID" "$REPO" "finalizing" "Iniciando finalizacao"
```

**Spawne @finalizer** (NAO faca deploy voce mesmo):

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/finalizer.md.
           PR: <PR_URL>
           Task: <TASK_ID>
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "sonnet"
)
```

Parse o JSON de retorno:
- `status: "deployed"` →
  ```bash
  wq_done_pr "$TASK_ID" "$REPO"
  if [ "$(wq_is_task_done "$TASK_ID")" = "true" ]; then
    TASKS_PROCESSED=$((TASKS_PROCESSED + 1))
  fi
  CONSECUTIVE_FAILURES=0
  ```
- Qualquer outro →
  ```bash
  wq_fail_pr "$TASK_ID" "$REPO" "<erro do JSON>"
  CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
  ```

#### Se ACTION = implement:

O /run-queue NAO implementa diretamente.
O /run-queue apenas:
1. verifica capacidade do queue
2. spawna o @orchestrator
3. recebe o resultado estruturado
4. registra no queue os artefatos produzidos (repo, branch, worktree, PR)

Toda selecao da task, avaliacao de clareza e coordenacao da implementacao tecnica pertencem ao @orchestrator e aos sub-agents que ele acionar.

Verifique limite de PRs ativas:

```bash
ACTIVE_WAITING=$(wq_count_waiting)
```

Se `$ACTIVE_WAITING >= $MAX_ACTIVE`:
- Exiba: "Limite de PRs ativas ($MAX_ACTIVE) atingido. Aguardando reviews..."
- Aguarde `$POLL_INTERVAL` segundos e volte ao inicio do loop.

Se pode pegar nova task — **spawne @orchestrator** (NAO busque tasks voce mesmo):

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/orchestrator.md.
           Diretorio de trabalho: <PWD>.
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "opus"
)
```

**CRITICAL:** Parse o JSON de retorno do orchestrator. Este passo e OBRIGATORIO — sem ele a PR fica orfã no GitHub sem monitoramento.

```bash
RESULT="<JSON retornado pelo orchestrator>"
STATUS=$(echo "$RESULT" | jq -r '.status // "unknown"')
```

- `status: "success"` → **OBRIGATORIO: registre no queue.**

  Suporte a single-repo e multi-repo: o orchestrator pode retornar um unico par `repo_name/pr_url`
  ou um array `prs` (multi-repo). Trate ambos os casos:

  ```bash
  TASK_ID=$(echo "$RESULT" | jq -r '.task_id')
  SLACK_TS=$(echo "$RESULT" | jq -r '.slack_ts // empty')

  # Validar task_id
  if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    echo "ERRO: orchestrator retornou success mas sem task_id"
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
  else
    # Normalizar: se vier prs[] usa ele, senao monta array a partir dos campos flat
    PRS=$(echo "$RESULT" | jq -r \
      '.prs // [{"repo": .repo_name, "pr_url": .pr_url, "branch": .branch, "worktree": .worktree_path}]')

    PR_COUNT=$(echo "$PRS" | jq 'length')
    if [ "$PR_COUNT" -eq 0 ]; then
      echo "ERRO: orchestrator retornou success mas sem PRs"
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    else
      echo "$PRS" | jq -c '.[]' | while read -r pr; do
        REPO_NAME=$(echo "$pr" | jq -r '.repo')
        PR_URL=$(echo "$pr" | jq -r '.pr_url')
        BRANCH=$(echo "$pr" | jq -r '.branch')
        WORKTREE=$(echo "$pr" | jq -r '.worktree')

        if [ -z "$PR_URL" ] || [ "$PR_URL" = "null" ]; then
          echo "AVISO: PR sem url para repo $REPO_NAME — ignorando"
          continue
        fi

        wq_add "$TASK_ID" "$REPO_NAME" "$BRANCH" "$WORKTREE"
        wq_set_pr "$TASK_ID" "$REPO_NAME" "$PR_URL"
        [ -n "$SLACK_TS" ] && wq_set_slack_ts "$TASK_ID" "$REPO_NAME" "$SLACK_TS"
        echo "PR registrada no queue: $TASK_ID ($REPO_NAME) → $PR_URL"
      done
      CONSECUTIVE_FAILURES=0
    fi
  fi
  ```

  **Se wq_add ou wq_set_pr nao forem chamados, a PR nunca sera monitorada.** Isso e um bug critico.

- `status: "no_task"` → sem tasks disponiveis. Aguarde `$POLL_INTERVAL` e volte ao loop. **NAO busque no backlog. NAO amplie a busca.**

- `status: "needs_clarity"` → task comentada no Jira, nao e uma falha. Aguarde `$POLL_INTERVAL` e volte ao loop.

- `status: "failed"` →
  ```bash
  CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
  ```

### 4. Status

Exiba status apos cada acao:

```
── Iteracao <N> ──────────────
Acao: <resolve|finalize|implement>
Task: <TASK_ID>
Resultado: <sucesso|falha|no_task|needs_clarity>

Queue:
  Implementando:     <N>
  Aguardando review: <N>
  Com feedback:      <N>
  Aprovadas:         <N>
  Concluidas:        <N>
  Falhas:            <N>

Progresso: <TASKS_PROCESSED>/<MAX_TASKS>
──────────────────────────────
```

Acao bem-sucedida reseta o circuit breaker (`CONSECUTIVE_FAILURES=0`).

---

## Dreno Final

Quando `TASKS_PROCESSED >= MAX_TASKS`, nao pegue mais tasks novas. Continue resolvendo PRs pendentes:

```bash
DRAIN_START=$(date +%s)
DRAIN_TIMEOUT=7200  # 2h em segundos

echo "Maximo de tasks atingido. Drenando queue — aguardando reviews pendentes..."

while [ "$(wq_count_active)" -gt 0 ]; do
  # Verificar timeout de dreno
  NOW=$(date +%s)
  if [ $((NOW - DRAIN_START)) -ge $DRAIN_TIMEOUT ]; then
    echo "Timeout de dreno atingido (2h). PRs ainda pendentes — reexecute /run-queue para retomar."
    break
  fi

  wq_poll_prs
  NEXT=$(wq_next_action)
  ACTION=$(echo "$NEXT" | jq -r '.action')

  if [ "$ACTION" = "resolve" ] || [ "$ACTION" = "finalize" ]; then
    # Spawne o agent correto (mesma logica do loop principal acima)
    : # executa resolve ou finalize conforme ACTION
  else
    # So waiting_review — aguarda
    sleep "$POLL_INTERVAL"
  fi
done
```

---

## Resumo Final

```
## Queue concluido

- **Tasks processadas:** <N>
- **PRs abertas:** <N>
- **PRs finalizadas:** <N>
- **PRs aguardando review:** <N> (pendentes)
- **Falhas:** <N>

### Tasks concluidas
| Task | PR | Status |
|------|----|--------|
| AZUL-1234 | https://... | done |

### Tasks pendentes
| Task | PR | Status |
|------|----|--------|
| AZUL-9999 | https://... | waiting_review |
```

Se houver tasks pendentes: **"Execute `/run-queue` novamente para retomar o monitoramento."**

---

## Regras (reforco)

- **NUNCA busque tasks no Jira diretamente.** Spawne @orchestrator.
- **NUNCA avalie clareza diretamente.** O @orchestrator faz via jira-task-clarity.
- **NUNCA busque no backlog.** no_task = aguarde e tente novamente.
- **NUNCA resolva comentarios de PR diretamente.** Spawne @pr-resolver.
- **NUNCA faca deploy diretamente.** Spawne @finalizer.
- **NUNCA leia ou escreva codigo.** Voce so gerencia o queue e spawna agents.
- Prioridade: resolver feedback > finalizar aprovadas > implementar nova.
- Circuit breaker: $CIRCUIT_BREAKER_THRESHOLD falhas consecutivas = parar.
- Queue persiste em ~/.ai-engineer/queue.db — sessoes podem ser retomadas.


$ARGUMENTS
