# Handoff: engineer -> pr-resolve

Template de transferência de contexto do `/engineer` para o `/pr-resolve`.

---

## Dados obrigatórios

```
TASK_ID=<chave Jira>
TASK_SUMMARY=<título da task>
PR_URL=<URL da PR aberta>
REPO_NAME=<nome do repositório>
BRANCH=<nome da branch>
BASE_BRANCH=<branch base (main/master)>
WORKTREE_PATH=<caminho do worktree>
```

## Contexto da implementação

```markdown
### Arquivos alterados
- <path/to/file1> — <o que foi feito>
- <path/to/file2> — <o que foi feito>

### Decisões técnicas
- <decisão 1 e justificativa>
- <decisão 2 e justificativa>

### Pontos de atenção para revisores
- <área que pode gerar dúvida>
- <trade-off que foi feito>

### Testes executados
- <teste 1>: PASS/FAIL
- <teste 2>: PASS/FAIL

### CI Status
- SonarQube: PASS/FAIL/PENDING
- Checks: PASS/FAIL/PENDING
```

## Como usar

O `/run` deve capturar essas informações do output da Etapa 14 do `/engineer` e passá-las como contexto ao invocar o `/pr-resolve`.

O `/pr-resolve` usa essas informações para:
1. Saber o caminho do worktree onde aplicar mudanças
2. Entender as decisões tomadas para responder revisores com contexto
3. Identificar pontos de atenção que podem gerar comentários
