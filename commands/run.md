# /run

Ciclo completo autonomo: implementa → resolve reviews → deploy.

## REGRAS ABSOLUTAS

1. **Voce NAO busca tasks no Jira.** O @orchestrator faz isso.
2. **Voce NAO avalia clareza.** O @orchestrator faz isso.
3. **Voce NAO le ou escreve codigo.** Os sub-agents fazem isso.
4. **Voce NAO resolve comentarios.** O @pr-resolver faz isso.
5. **Voce NAO faz deploy.** O @finalizer faz isso.
6. **Voce APENAS spawna agents em sequencia e le retornos JSON.**

---

## Fase 1 — Implementar

Spawne o sub-agent `orchestrator`:

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/orchestrator.md.
           Diretorio de trabalho: <PWD>.
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "opus"
)
```

Capture: task_id, pr_url, worktree_path.

- `status: "no_task"` → encerre: "Nenhuma task disponivel."
- `status: "needs_clarity"` → encerre: "Task comentada. Aguardando resposta."
- `status: "failed"` → encerre com erro.
- `status: "success"` → prossiga.

Persista o handoff:

```bash
source ~/.ai-engineer/scripts/execution-log.sh
exec_handoff_save "$TASK_ID" "orchestrator" "pr-resolver" \
  "pr_url=$PR_URL" "worktree=$WORKTREE_PATH"
```

---

## Fase 2 — Resolver Reviews

Spawne o sub-agent `pr-resolver`:

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/pr-resolver.md.
           PR: <PR_URL>
           Task: <TASK_ID>
           Worktree: <WORKTREE_PATH>
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "opus"
)
```

- `status: "approved"` → prossiga.
- `status: "timeout"` → encerre: "PR sem revisao em 24h."
- `status: "failed"` → encerre com erro.

---

## Fase 3 — Deploy

Spawne o sub-agent `finalizer`:

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

---

## Resumo Final

Exiba:
```
Task: <task_id> — <summary>
PR: <pr_url> (merged)
Deploy: producao OK
Jira: Done
```

$ARGUMENTS
