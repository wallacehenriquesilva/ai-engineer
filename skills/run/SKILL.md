---
name: run
version: 1.1.0
description: >
  Executa o ciclo completo de desenvolvimento de forma autônoma:
  implementa a task, resolve comentários de revisão e finaliza com deploy.
  Invoca engineer → pr-resolve → finalize em sequência.
  Uso: /run
depends-on:
  - engineer
  - pr-resolve
  - finalize
triggers:
  - user-command: /run
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

# run: Ciclo Completo Autônomo

Executa o ciclo completo de desenvolvimento sem intervenção manual.
Cada fase depende do sucesso da anterior — se uma falhar, o ciclo encerra.

---

## Fase 1 — Implementação

Invoque a skill `/engineer` e aguarde a conclusão.

O `/engineer` irá:
- Buscar a próxima task disponível
- Avaliar clareza
- Implementar, testar e abrir a PR
- Acionar o CI e aguardar o SonarQube
- Mover a task para `Em Revisão`

Ao final, capture os dados de handoff do output da Etapa 14 do `/engineer` (veja [handoff template](templates/engineer-to-pr-resolve.md)):

```
TASK_ID, TASK_SUMMARY, PR_URL, REPO_NAME, BRANCH, BASE_BRANCH, WORKTREE_PATH
```

Também capture: arquivos alterados, decisões técnicas e pontos de atenção.

### Se `/engineer` encerrar sem PR aberta:
- Task não encontrada → encerre com: **"Nenhuma task disponível. Ciclo encerrado."**
- Task sem clareza → encerre com: **"Task comentada com perguntas. Ciclo encerrado até ajuste."**
- Falha irrecuperável → preencha o [template de escalação](templates/escalation.md) e encerre.

---

## Fase 2 — Revisão

Com a `<PR-URL>` e o contexto de handoff da Fase 1, invoque `/pr-resolve <PR-URL>` e passe as decisões técnicas e pontos de atenção como contexto.

O `/pr-resolve` irá:
- Monitorar a PR aguardando comentários ou aprovação do time
- Resolver comentários, responder dúvidas e pedir clareza quando necessário
- Rodar o CI novamente após cada push
- Aguardar aprovação final

Ao final, capture os dados de handoff (veja [handoff template](templates/pr-resolve-to-finalize.md)):

```
Revisores que aprovaram, comentários resolvidos, commits de fix, CI final
```

### Se `/pr-resolve` encerrar sem aprovação:
- Timeout de 24h sem feedback → encerre com: **"PR sem revisão em 24h. Intervenção manual necessária."**
- Falha de CI irrecuperável → preencha o [template de escalação](templates/escalation.md) e encerre.

---

## Fase 3 — Finalização

Com a `<PR-URL>` aprovada, invoque `/finalize <PR-URL>` e aguarde a conclusão.

O `/finalize` irá:
- Validar aprovação
- Fazer deploy em sandbox e homolog
- Gerar evidências de funcionamento
- Atualizar o Jira e fazer o merge
- Acompanhar o deploy em produção

### Se `/finalize` falhar:
- Preencha o [template de escalação](templates/escalation.md) e encerre com orientação de intervenção manual.

---

## Resumo Final

Ao concluir com sucesso todas as fases, exiba:

```
## ✅ Ciclo completo concluído

- **Task:** <KEY> — <summary>
- **PR:** <PR-URL> (merged)
- **Sandbox:** ✅
- **Homolog:** ✅
- **Produção:** ✅
- **Status Jira:** Done

Duração total: <tempo desde o início>
```

---

## Persistência de Estado entre Fases

Use `execution-log.sh` para persistir handoff state entre skills. Isso permite recuperação se a sessão for interrompida.

```bash
source scripts/execution-log.sh

# Após Fase 1 (engineer concluído):
exec_handoff_save "$TASK_ID" "engineer" "pr-resolve" \
  "pr_url=$PR_URL" "repo=$REPO_NAME" "branch=$BRANCH" \
  "base_branch=$BASE_BRANCH" "worktree=$WORKTREE_PATH"

# Antes da Fase 2 (recuperar contexto se sessão reiniciou):
PR_URL=$(exec_handoff_get "$TASK_ID" "pr_url")

# Após Fase 2 (pr-resolve concluído):
exec_handoff_save "$TASK_ID" "pr-resolve" "finalize" \
  "pr_url=$PR_URL" "approved_by=$APPROVED_BY" "fix_commits=$FIX_COMMITS"

# Após Fase 3 (ciclo concluído):
exec_handoff_clean "$TASK_ID"
```

---

## Regras

- Nunca pule uma fase — cada uma depende da anterior.
- Persista o estado entre fases via `exec_handoff_save` — não dependa apenas de variáveis em memória.
- Em caso de falha em qualquer fase, preencha o template de escalação e encerre.
- As skills individuais (/engineer, /pr-resolve, /finalize) continuam disponíveis para execução isolada.
