---
name: run-parallel
version: 1.0.0
description: >
  Executa múltiplas tasks em paralelo, cada uma em um worker isolado.
  Busca N tasks disponíveis na sprint e lança agentes paralelos para implementá-las.
  Uso: /run-parallel [--workers 3]
depends-on:
  - engineer
  - jira-integration
triggers:
  - user-command: /run-parallel
allowed-tools:
  - Bash
  - Read
  - Agent
  - Skill
  - TaskCreate
  - TaskUpdate
  - mcp__mcp-atlassian__jira_*
  - mcp__github__*
---

# run-parallel: Execução Paralela de Tasks

Busca múltiplas tasks disponíveis e as implementa em paralelo usando agentes isolados.

---

## Etapa 0 — Validar Pré-condições

```bash
gh auth status 2>&1 | head -3
command -v jq >/dev/null && echo "jq OK" || echo "jq NOT FOUND"
test -f CLAUDE.md && echo "config OK" || echo "config MISSING"
```

Se `CLAUDE.md` não existir: **"Execute /engineer primeiro para criar as configurações."**

---

## Etapa 1 — Carregar Configurações

```bash
JIRA_BOARD=$(grep "Jira Board:" CLAUDE.md | awk '{print $NF}')
JIRA_PROJECT=$(grep "Jira Project:" CLAUDE.md | awk '{print $NF}')
AI_LABEL=$(grep "Label IA:" CLAUDE.md | awk '{print $NF}')
BACKEND_LABELS=$(grep "Labels backend:" CLAUDE.md | sed 's/.*Labels backend: //')
```

---

## Etapa 2 — Determinar Número de Workers

Parse o argumento `--workers` da mensagem do usuário. Default: **3**.

Máximo permitido: **5** (para evitar throttling de APIs).

---

## Etapa 3 — Buscar Tasks Disponíveis

Use `jira-integration` (Seção A) para buscar tasks, mas em vez de selecionar apenas a primeira, liste todas as disponíveis (até o número de workers).

Para cada task candidata:
1. Verifique bloqueios (issue links com `is blocked by` não-Done)
2. Verifique se não está atribuída a outro agente (status `Fazendo`)
3. Selecione as primeiras N válidas

Se menos tasks que workers: reduza o número de workers.

Se nenhuma task: **"Nenhuma task disponível para execução paralela."**

---

## Etapa 4 — Mover Tasks para "Fazendo"

Para cada task selecionada, mova para `Fazendo` via `jira_transition_issue`.

Isso "reserva" as tasks antes de lançar os workers, evitando que outro agente pegue a mesma task.

---

## Etapa 5 — Lançar Workers em Paralelo

Para cada task, lance um **Agent** com `subagent_type: "general-purpose"` e `isolation: "worktree"`:

```
Prompt para cada agent:
"Execute o ciclo completo de implementação para a task <TASK-ID>.
 Repositório: <repo>
 Branch: <TASK-ID>/<descricao-kebab-case>

 Siga estas etapas:
 1. Localize o repositório (clone se necessário)
 2. Crie worktree isolado
 3. Faça commit vazio para DORA metrics
 4. Analise o código e planeje
 5. Implemente seguindo padrões do CLAUDE.md do repo
 6. Rode os testes
 7. Faça commits atômicos
 8. Abra a PR com label ai-generated
 9. Acione CI com /ok-to-test
 10. Aguarde SonarQube (máximo 2 tentativas de correção)

 Retorne: {task: '<TASK-ID>', status: 'success|failure', pr_url: '<URL>', error: '<motivo se falhou>'}"
```

Lance **todos os agents em uma única mensagem** para máximo paralelismo.

---

## Etapa 6 — Coletar Resultados

À medida que cada agent completar, colete o resultado:

- **Sucesso:** registre a PR-URL
- **Falha:** registre o motivo e a etapa

---

## Etapa 7 — Atualizar Jira

Para cada task com sucesso:
1. Mova para `Em Revisão`
2. Comente com o link da PR

Para cada task com falha:
1. Mova de volta para `To Do`
2. Comente com o motivo da falha

---

## Etapa 8 — Registrar Execuções

```bash
source ~/.ai-engineer/scripts/execution-log.sh
```

Para cada worker, registre a execução (sucesso ou falha) usando `exec_log_start` + `exec_log_end`/`exec_log_fail`.

---

## Etapa 9 — Relatório Final

```
## Execução Paralela Concluída

| # | Task       | Repo                        | Status | PR                                    |
|---|------------|-----------------------------|--------|---------------------------------------|
| 1 | AZUL-1234  | martech-integration-worker  | ✅     | https://github.com/.../pull/42        |
| 2 | AZUL-1235  | notification-hub            | ✅     | https://github.com/.../pull/18        |
| 3 | AZUL-1236  | link-shortener              | ❌     | —                                     |

**Sucesso:** 2/3
**Falhas:**
> ❌ AZUL-1236: Falha na Etapa 9 — teste de integração falhou após 2 tentativas
```

---

## Regras

- Máximo 5 workers simultâneos — APIs do Jira e GitHub têm rate limits.
- Cada worker opera em worktree isolado — nunca compartilham branches.
- Tasks são reservadas (movidas para Fazendo) ANTES de lançar workers.
- Se um worker falha, os outros continuam — falhas são independentes.
- Sempre registre execuções no execution-log para rastreabilidade.
- Nunca lance workers para tasks do mesmo repositório — worktrees do mesmo repo podem conflitar.
