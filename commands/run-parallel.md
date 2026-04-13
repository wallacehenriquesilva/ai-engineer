# /run-parallel

Executa multiplas tasks em paralelo, cada uma em um worker isolado.

## Flags

- `--workers <N>` → Numero de workers paralelos (padrao: 3, max: 5)

## Instrucoes

### 1. Buscar N tasks

Para cada worker, spawne um `@task-fetcher` para buscar uma task diferente.

### 2. Spawnar workers em paralelo

Para cada task, spawne um `@orchestrator` em paralelo:

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/orchestrator.md.
           Task especifica: <TASK_ID> (ja buscada, nao busque outra).
           TaskContext: <JSON>
           Diretorio de trabalho: <PWD>.
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "sonnet",
  isolation: "worktree"
)
```

Use `isolation: "worktree"` para evitar conflitos entre workers.

### 3. Coletar resultados

Aguarde todos os workers e exiba:

```
Worker 1: AZUL-1234 | PR #123 | success
Worker 2: AZUL-5678 | PR #456 | success
Worker 3: AZUL-9999 | no_task
```

$ARGUMENTS
