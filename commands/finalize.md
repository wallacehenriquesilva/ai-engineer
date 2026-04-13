# /finalize

Deploy e merge de uma PR aprovada.

## Instrucoes

Spawne o sub-agent `finalizer`:

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/finalizer.md.
           PR: <PR_URL extraida de $ARGUMENTS>
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "sonnet"
)
```

Exiba o resultado: ambientes deployados, status Jira.

$ARGUMENTS
