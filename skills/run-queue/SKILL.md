---
name: run-queue
version: 1.0.0
description: >
  Executa tasks de forma contínua sem bloquear esperando review.
  Implementa uma task, abre PR, e em vez de esperar, pega a próxima.
  PRs são monitoradas em background e priorizadas quando recebem feedback.
  Uso: /run-queue [--max-tasks 10] [--max-active 5]
depends-on:
  - engineer
  - pr-resolve
  - finalize
  - jira-integration
triggers:
  - user-command: /run-queue
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - TaskCreate
  - TaskUpdate
  - mcp__mcp-atlassian__jira_*
  - mcp__github__*
---

# run-queue: Execução Contínua com Work Queue

Executa tasks de forma contínua e não-bloqueante. Em vez de esperar revisão de uma PR por horas, o agente pega a próxima task disponível e monitora as PRs abertas em background.

## Flags

- `--max-tasks <N>` → Máximo de tasks a processar no total (padrão: 10)
- `--max-active <N>` → Máximo de PRs ativas simultaneamente em `waiting_review` (padrão: 5)
- `--poll-interval <S>` → Intervalo de polling das PRs em segundos (padrão: 60)

---

## Etapa 0 — Inicializar

### 0.1 — Carregar configurações

```bash
test -f CLAUDE.md && echo "exists" || echo "missing"
```

Se não existir → encerre com: **"CLAUDE.md não encontrado. Execute /engineer primeiro."**

```bash
JIRA_BOARD=$(grep "Jira Board:" CLAUDE.md | awk '{print $NF}')
AI_LABEL=$(grep "Label IA:" CLAUDE.md | awk '{print $NF}')
BUDGET_LIMIT=$(grep "Budget limit:" CLAUDE.md | grep -oE '[0-9]+\.[0-9]+' || echo "5.00")
CIRCUIT_BREAKER_THRESHOLD=$(grep "Circuit breaker:" CLAUDE.md | grep -oE '[0-9]+' | head -1 || echo "3")
```

### 0.2 — Inicializar work queue

```bash
source ~/.ai-engineer/scripts/work-queue.sh
wq_init
```

**CRITICAL:** Use APENAS as funções listadas abaixo. NÃO invente funções ou tabelas que não existem. A tabela se chama `work_items` (NÃO `queue`, NÃO `work_queue`).

Funções disponíveis no `work-queue.sh`:

| Função | Uso |
|--------|-----|
| `wq_init` | Inicializa o banco (criar tabelas, migrar schema) |
| `wq_add <task_id> <repo> [branch] [worktree]` | Adiciona item ao queue |
| `wq_set_pr <task_id> <repo> <pr_url>` | Define PR URL e muda status para waiting_review |
| `wq_update_pr <task_id> <repo> <status> [reason]` | Atualiza status de um item |
| `wq_update <task_id> <status> [reason]` | Atualiza status de TODOS os items de uma task |
| `wq_get <task_id>` | Retorna todos os items de uma task (JSON) |
| `wq_get_pr <task_id> <repo>` | Retorna um item específico (JSON) |
| `wq_list [status]` | Lista items por status ou todos os ativos (JSON) |
| `wq_count_active` | Conta items ativos (não done/failed) |
| `wq_count_waiting` | Conta items em waiting_review |
| `wq_done_pr <task_id> <repo>` | Marca item como done |
| `wq_fail_pr <task_id> <repo> [reason]` | Marca item como failed |
| `wq_is_task_done <task_id>` | Retorna "true" se TODAS as PRs da task estão done |
| `wq_task_summary <task_id>` | Resumo agregado de uma task (JSON) |
| `wq_set_slack_ts <task_id> <repo> <ts>` | Salva o timestamp da mensagem de review no Slack |
| `wq_get_slack_ts <task_id> <repo>` | Retorna o timestamp para responder na thread do Slack |
| `wq_next_action` | Retorna próxima ação prioritária (JSON: action, task_id, repo, pr_url) |
| `wq_poll_prs` | Verifica status de todas as PRs pendentes via GitHub |
| `wq_summary` | Resumo do queue por status (texto) |
| `wq_summary_json` | Resumo do queue (JSON com contadores) |
| `wq_history [task_id]` | Log de transições (JSON) |
| `wq_cleanup [days]` | Remove items done/failed mais antigos que N dias |

### 0.3 — Verificar estado anterior

O queue persiste entre sessões. Verifique se há trabalho pendente de uma execução anterior:

```bash
ACTIVE=$(wq_count_active)
SUMMARY=$(wq_summary_json)
echo "$SUMMARY" | jq '.'
```

Para ver os items ativos com detalhes:

```bash
wq_list | jq '.[] | {task_id, repo, pr_url, status}'
```

Se `$ACTIVE > 0`:

```
Queue existente detectado:
- Implementando: <N>
- Aguardando review: <N>
- Com feedback: <N>
- Aprovadas: <N>

Items ativos:
<lista dos items com task_id, repo, status>

Retomando de onde parou.
```

Se `$ACTIVE = 0` → queue limpo, começar do zero.

### 0.4 — Parsear flags

```bash
MAX_TASKS=${MAX_TASKS:-10}
MAX_ACTIVE=${MAX_ACTIVE:-5}
POLL_INTERVAL=${POLL_INTERVAL:-60}
TASKS_PROCESSED=0
CONSECUTIVE_FAILURES=0
```

---

## Etapa 1 — Loop Principal

Repita até `$TASKS_PROCESSED >= $MAX_TASKS` ou circuit breaker disparar:

```
ENQUANTO tasks_processed < max_tasks E consecutive_failures < circuit_breaker:

  1. Pollar PRs pendentes
  2. Determinar próxima ação
  3. Executar ação
  4. Atualizar contadores

FIM
```

### 1.1 — Pollar PRs

```bash
wq_poll_prs
```

Isso verifica todas as PRs em `waiting_review` e atualiza o status no queue:
- PR aprovada → `approved`
- Changes requested / comentários novos → `has_feedback`
- PR merged/closed externamente → `done`

### 1.2 — Determinar próxima ação

```bash
NEXT=$(wq_next_action)
ACTION=$(echo "$NEXT" | jq -r '.action')
```

| Ação | Significado |
|------|-------------|
| `resolve` | Uma PR tem feedback — resolver comentários é prioridade |
| `finalize` | Uma PR foi aprovada — finalizar é prioridade |
| `implement` | Nenhuma ação urgente — pegar nova task |

### 1.3 — Executar ação

#### Se `ACTION = resolve`:

```bash
TASK_ID=$(echo "$NEXT" | jq -r '.task_id')
PR_URL=$(echo "$NEXT" | jq -r '.pr_url')
REPO=$(echo "$NEXT" | jq -r '.repo')
wq_update_pr "$TASK_ID" "$REPO" "implementing" "Resolvendo feedback"
```

**CRITICAL:** Invoque `/pr-resolve <PR-URL> --no-poll`. A flag `--no-poll` é obrigatória — sem ela o pr-resolve entra em polling de 24h e trava o queue.

O que o pr-resolve faz com `--no-poll`:
1. Carrega contexto da PR (Etapa 1)
2. Localiza worktree (Etapa 2)
3. **Pula o polling** (Etapa 3)
4. Analisa os comentários existentes (Etapa 4)
5. Resolve: implementa, faz commit, responde, marca threads como resolvidos (Etapa 5)
6. Push + aguarda CI (Etapa 6)
7. **Retorna** em vez de voltar ao polling

Após retorno com sucesso:

```bash
wq_update_pr "$TASK_ID" "$REPO" "waiting_review" "Feedback resolvido, aguardando re-review"
```

Após falha:

```bash
wq_fail_pr "$TASK_ID" "$REPO" "<motivo>"
CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
```

#### Se `ACTION = finalize`:

```bash
TASK_ID=$(echo "$NEXT" | jq -r '.task_id')
PR_URL=$(echo "$NEXT" | jq -r '.pr_url')
REPO=$(echo "$NEXT" | jq -r '.repo')
wq_update_pr "$TASK_ID" "$REPO" "finalizing" "Iniciando finalização"
```

Invoque `/finalize <PR-URL>`.

Após concluir:

```bash
wq_done_pr "$TASK_ID" "$REPO"

# Verificar se TODAS as PRs da task estão concluídas
if [ "$(wq_is_task_done "$TASK_ID")" = "true" ]; then
  TASKS_PROCESSED=$((TASKS_PROCESSED + 1))
fi
```

Se falhar:

```bash
wq_fail_pr "$TASK_ID" "$REPO" "<motivo>"
CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
```

#### Se `ACTION = implement`:

Verifique se pode pegar nova task:

```bash
ACTIVE_WAITING=$(wq_count_waiting)
```

Se `$ACTIVE_WAITING >= $MAX_ACTIVE`:
- **Não pegue nova task** — limite de PRs ativas atingido
- Aguarde `$POLL_INTERVAL` segundos e volte ao início do loop
- Exiba: **"Limite de PRs ativas ($MAX_ACTIVE) atingido. Aguardando reviews..."**

Se pode pegar:

Invoque `/engineer` para implementar a próxima task.

Após PR aberta (pode ser 1 ou mais PRs se multi-repo):

```bash
# Para cada PR aberta pelo engineer:
wq_add "$TASK_ID" "$REPO_NAME" "$BRANCH" "$WORKTREE_PATH"
wq_set_pr "$TASK_ID" "$REPO_NAME" "$PR_URL"

# Se multi-repo, repita para cada repo:
# wq_add "$TASK_ID" "$REPO_INFRA" "$BRANCH_INFRA" "$WORKTREE_INFRA"
# wq_set_pr "$TASK_ID" "$REPO_INFRA" "$PR_URL_INFRA"
```

Se `/engineer` encerrar sem PR (sem task, sem clareza):

```bash
# Sem tasks disponíveis — aguardar e tentar novamente
sleep $POLL_INTERVAL
```

Se `/engineer` falhar:

```bash
wq_fail "$TASK_ID" "<motivo>"
CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
```

### 1.4 — Reset de circuit breaker

Qualquer ação bem-sucedida reseta o contador:

```bash
CONSECUTIVE_FAILURES=0
```

### 1.5 — Status entre iterações

Após cada ação, exiba o status atual:

```
── Iteração <N> ──────────────────────────
Ação: <resolve|finalize|implement>
Task: <TASK-ID>
Resultado: <sucesso|falha>

Queue:
  Implementando:      <N>
  Aguardando review:  <N>
  Com feedback:       <N>
  Aprovadas:          <N>
  Concluídas:         <N>
  Falhas:             <N>

Progresso: <TASKS_PROCESSED>/<MAX_TASKS>
──────────────────────────────────────────
```

---

## Etapa 2 — Dreno Final

Quando `$TASKS_PROCESSED >= $MAX_TASKS`, não pegue mais tasks novas, mas continue resolvendo o que está no queue:

```
ENQUANTO existem tasks ativas (não done/failed):

  1. Poll PRs
  2. Se tem ação (resolve/finalize) → executa
  3. Se só waiting_review → aguarda $POLL_INTERVAL e repete
  4. Timeout de dreno: 2h (se nenhuma PR receber feedback em 2h, encerre)

FIM
```

Exiba: **"Máximo de tasks atingido. Drenando queue — aguardando reviews pendentes..."**

---

## Etapa 3 — Resumo Final

```
## Queue concluído

- **Tasks processadas:** <N>
- **PRs abertas:** <N>
- **PRs aprovadas e finalizadas:** <N>
- **PRs aguardando review:** <N> (pendentes)
- **Falhas:** <N>
- **Duração total:** <tempo>

### Tasks concluídas
| Task | PR | Status |
|------|----|--------|
| AZUL-1234 | https://... | done |
| AZUL-5678 | https://... | done |

### Tasks pendentes (aguardando review)
| Task | PR | Status |
|------|----|--------|
| AZUL-9999 | https://... | waiting_review |
```

Se houver tasks pendentes: **"Execute `/run-queue` novamente para retomar o monitoramento."**

---

## Regras

- **Nunca bloqueie esperando review** — se não há ação urgente e o limite de PRs ativas não foi atingido, pegue nova task.
- **Prioridade absoluta:** resolver feedback > finalizar aprovadas > implementar nova.
- **Limite de PRs ativas** (`--max-active`) evita abrir PRs demais sem review — respeite o time.
- **Circuit breaker** do CLAUDE.md se aplica: N falhas consecutivas = parar.
- **O queue persiste** em `~/.ai-engineer/queue.db` — sessões podem ser retomadas.
- **Nunca force push, nunca commite na main.**
- **Cada task usa seu próprio worktree** — não há conflito entre implementações.
- **Todo comentário é feedback** — trate comentários de bots (Aikido, SonarQube, etc.) da mesma forma que comentários humanos. Resolva, implemente a sugestão, ou responda justificando por que não se aplica. **NUNCA** ignore um comentário sem ação.
- **PRs devem estar green** — ao resolver feedback, ou abrir uma nova PR, verifique também os CI checks (`gh pr checks`). Se algum check falhou, diagnostique e corrija antes de considerar a PR pronta. Checks falhando têm a mesma prioridade que comentários de reviewer.