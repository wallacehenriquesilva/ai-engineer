# /pr-resolve

Resolve comentarios de revisao de uma PR.

## Instrucoes

Spawne o sub-agent `pr-resolver`:

```
Agent(
  prompt: "Leia e siga ~/.claude/agents/pr-resolver.md.
           PR: <PR_URL extraida de $ARGUMENTS>
           Retorne o JSON estruturado.",
  subagent_type: "general-purpose",
  model: "opus"
)
```

Exiba o resultado: status, comentarios resolvidos, CI status.

$ARGUMENTS
