# Handoff: pr-resolve -> finalize

Template de transferência de contexto do `/pr-resolve` para o `/finalize`.

---

## Dados obrigatórios

```
TASK_ID=<chave Jira>
PR_URL=<URL da PR aprovada>
REPO_NAME=<nome do repositório>
BRANCH=<nome da branch>
BASE_BRANCH=<branch base>
```

## Contexto da revisão

```markdown
### Aprovação
- Revisores que aprovaram: <lista>
- Data da aprovação: <timestamp>

### Comentários resolvidos
- Total: <N>
- Commits de fix: <N>
- Mudanças significativas pós-review: <sim/não>

### CI Final
- SonarQube: PASS
- Checks: PASS
- Última execução: <timestamp>

### Riscos identificados na revisão
- <risco 1, se houver>
- <nenhum identificado>
```

## Como usar

O `/run` deve capturar essas informações do output da Etapa 8 do `/pr-resolve` e passá-las como contexto ao invocar o `/finalize`.

O `/finalize` usa essas informações para:
1. Confirmar que a PR está de fato aprovada antes de prosseguir
2. Avaliar se houve mudanças significativas que requerem atenção extra no deploy
3. Incluir contexto de revisão no comentário do Jira
