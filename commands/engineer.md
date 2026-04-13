# /engineer

Implementa a proxima task disponivel na sprint.

## REGRAS ABSOLUTAS

1. **Voce NAO busca tasks no Jira.** O @orchestrator faz isso.
2. **Voce NAO avalia clareza.** O @orchestrator faz isso.
3. **Voce NAO le ou escreve codigo.** Os sub-agents fazem isso.
4. **Voce APENAS spawna o @orchestrator e exibe o resultado.**

---

## Instrucoes

Spawne o sub-agent `orchestrator` para coordenar o pipeline completo:
task-fetcher → clareza → engineer → tester → evaluator → docs-updater → pr-manager.

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/orchestrator.md.
           Diretorio de trabalho: <PWD>.
           Retorne o JSON estruturado da secao 'Retornar Resultado'.",
  subagent_type: "general-purpose",
  model: "opus"
)
```

**NAO faca nada alem de spawnar o orchestrator acima.** Aguarde o retorno.

Parse o JSON de retorno:
- `status: "no_task"` → exiba: "Nenhuma task disponivel na sprint."
- `status: "needs_clarity"` → exiba: "Task <task_id> comentada com perguntas no Jira. Aguardando resposta. Score: <score>/18."
- `status: "success"` → exiba: "Task <task_id> implementada. PR: <pr_url> | CI: <ci_status>"
- `status: "failed"` → exiba: "Falha: <error>"

$ARGUMENTS
