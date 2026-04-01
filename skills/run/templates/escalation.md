# Handoff: Escalação (qualquer skill -> falha)

Template de escalação quando uma skill falha de forma irrecuperável.

---

## Dados obrigatórios

```
TASK_ID=<chave Jira>
SKILL=<skill que falhou (engineer/pr-resolve/finalize)>
FAILED_STEP=<número da etapa onde falhou>
PR_URL=<URL da PR, se existir>
REPO_NAME=<nome do repositório>
```

## Relatório de escalação

```markdown
### O que aconteceu
<Descrição objetiva do que a skill tentou fazer e o que falhou>

### Causa raiz
- **Tipo:** <código/infra/dependência/clareza/permissão>
- **Detalhe:** <descrição técnica da causa>

### O que foi tentado
1. <tentativa 1 — resultado>
2. <tentativa 2 — resultado>
3. <tentativa 3 — resultado (se aplicável)>

### Estado atual
- Branch: <existe/não existe>
- PR: <aberta/não criada/draft>
- CI: <último status>
- Worktree: <preservado em path>
- Task no Jira: <status atual>

### Ação necessária
- [ ] <ação 1 que o humano precisa tomar>
- [ ] <ação 2>

### Aprendizado registrado
- execution-feedback: <sim/não>
- Motivo: <resumo do aprendizado para evitar recorrência>
```

## Quando escalar

| Skill | Condição de escalação |
|-------|----------------------|
| engineer | Falha na implementação após plano, testes falham após 2 correções, CI falha após `$CI_MAX_RETRIES` |
| pr-resolve | CI falha após `$CI_MAX_RETRIES` correções, comentário ambíguo sem resposta em 24h |
| finalize | Deploy falha em sandbox/homolog, checks de produção falham |

## Como usar

1. A skill que falhou preenche este template
2. Registra via `exec_log_fail` com step e reason
3. Registra aprendizado via `execution-feedback`
4. Comenta na task do Jira mencionando `$CLARITY_OWNERS`
5. Move a task de volta para `To Do`
