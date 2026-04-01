---
name: git-workflow
version: 1.1.0
description: >
  Gerencia o fluxo Git completo para implementação de tasks: criação de worktree, branch,
  commits semânticos atômicos, abertura de PR e monitoramento de CI.
  Acione esta skill quando precisar criar uma branch, fazer commits, abrir PR,
  ou acompanhar o resultado dos testes de CI de uma pull request.
depends-on: []
triggers:
  - called-by: engineer
  - called-by: engineer-multi
  - called-by: pr-resolve
  - called-by: finalize
context: default
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - mcp__mcp-atlassian__jira_get_issue_transitions
  - mcp__mcp-atlassian__jira_transition_issue
  - mcp__mcp-atlassian__jira_add_comment
---

# Git Workflow

Gerencia o ciclo completo de versionamento para uma task, desde o worktree até a PR aprovada pelo CI.

## 1. Criar Worktree e Branch

### Detectar branch base

Antes de criar o worktree, detecte a branch base do repositório automaticamente:

```bash
BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$BASE_BRANCH" ]; then
  BASE_BRANCH="main"
fi
```

### Criar ou reutilizar worktree

Verifique se já existe um worktree para a task antes de criar:

```bash
WORKTREE_PATH="../<task-id>"

if git worktree list | grep -q "$WORKTREE_PATH"; then
  cd "$WORKTREE_PATH"
else
  git worktree add "$WORKTREE_PATH" "$BASE_BRANCH"
  cd "$WORKTREE_PATH"
fi
```

### Criar branch

Use o padrão obrigatório:

```
<TASK-ID>/<descricao-curta-em-kebab-case>
```

Exemplos:
- `AZUL-1234/consumer-whatsapp-reply`
- `AZUL-9999/add-health-check-endpoint`

```bash
git checkout -b <TASK-ID>/<descricao>
```

Se a branch já existir remotamente, faça checkout dela em vez de criar uma nova.

---

## 2. Commits Semânticos e Atômicos

Cada commit deve ter escopo único e mensagem clara. Use os prefixos:

| Prefixo | Quando usar |
|---|---|
| `feat:` | Nova funcionalidade |
| `fix:` | Correção de bug |
| `test:` | Adição ou ajuste de testes |
| `docs:` | Documentação |
| `refactor:` | Refatoração sem mudança de comportamento |
| `chore:` | Tarefas de manutenção (configs, deps) |

Exemplos:
- `feat: add NOTIFICATION-HUB-WHATSAPP_MESSAGE_REPLY_CREATED consumer`
- `test: add unit tests for whatsapp reply consumer`
- `docs: update README with whatsapp reply consumer info`

### Co-autoria de AI

Commits que contenham código gerado por AI devem incluir o trailer de co-autoria. Se todas as linhas do commit foram escritas manualmente pelo desenvolvedor, **não** adicione o co-author.

O formato exato é (atenção à linha em branco obrigatória antes do trailer):

```
feat: add whatsapp reply consumer

Add SQS consumer for WHATSAPP_MESSAGE_REPLY_CREATED events.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
```

Para um exemplo real de commit com co-author, veja [examples/commit-example.md](examples/commit-example.md).

### Regras de commit

- Um commit por responsabilidade — nunca agrupe mudanças não relacionadas
- Nunca commite arquivos de ambiente (`.env`, secrets)
- Sempre verifique o diff antes de commitar: `git diff --staged`

---

## 3. Push e Pull Request

### Push da branch

Antes de abrir a PR, faça push da branch para o remote:

```bash
git push -u origin <TASK-ID>/<descricao>
```

### Resolver conflitos com a branch base

Se a branch base avançou e há conflitos, resolva com merge (nunca rebase):

```bash
git fetch origin "$BASE_BRANCH"
git merge "origin/$BASE_BRANCH"
```

Resolva os conflitos mantendo as mudanças da branch base e ajustando o seu código para ser compatível. Após resolver, faça commit do merge e push.

### Abrir a PR

Use o template do time disponível em [templates/pr-template.md](templates/pr-template.md). Preencha com base na task e nas mudanças implementadas. Para referência de como uma PR real deve ficar, veja [examples/pr-example.md](examples/pr-example.md).

O título da PR deve ser em inglês. O body (descrição) deve ser em **PT-BR**.

### Label obrigatória de participação de AI

**CRITICAL:** Toda PR deve ter exatamente uma das labels abaixo. A escolha é baseada nos commits da branch:

| Label | Critério |
|---|---|
| `ai-first` | **Todos** os commits têm `Co-Authored-By: Claude`. Código 100% gerado por AI — o dev revisou e aprovou, mas não escreveu código. |
| `ai-assisted` | **Alguns** commits têm `Co-Authored-By: Claude`. Dev e AI trabalharam juntos — parte escrita pelo dev, parte pela AI. |
| `ai-none` | **Nenhum** commit tem `Co-Authored-By: Claude`. Código 100% escrito pelo dev. |

Para determinar a label, verifique os commits da branch:

```bash
TOTAL=$(git log "$BASE_BRANCH"..HEAD --oneline | wc -l | tr -d ' ')
AI_COMMITS=$(git log "$BASE_BRANCH"..HEAD --grep="Co-Authored-By: Claude" --oneline | wc -l | tr -d ' ')

if [ "$AI_COMMITS" -eq 0 ]; then
  AI_LABEL="ai-none"
elif [ "$AI_COMMITS" -eq "$TOTAL" ]; then
  AI_LABEL="ai-first"
else
  AI_LABEL="ai-assisted"
fi
```

### Criar a PR

**CRITICAL:** O título da PR DEVE seguir exatamente o formato `<TASK-ID> | <descricao em ingles>`. Não use prefixos de commit (feat:, fix:), não omita o TASK-ID, e não mude a ordem.

Exemplos:
- ✅ `PROJ-1234 | Add CNPJ validation endpoint`
- ✅ `PROJ-567 | Fix duplicated SQS messages on retry`
- ❌ `feat: add CNPJ validation endpoint`
- ❌ `Add CNPJ validation endpoint (PROJ-1234)`
- ❌ `PROJ-1234 - Add CNPJ validation endpoint`
- ❌ `PROJ-1234: Add CNPJ validation endpoint`

Abra a PR via CLI usando a branch base detectada e a label de AI:

```bash
gh pr create \
  --title "<TASK-ID> | <descricao em ingles>" \
  --body "<conteudo do template preenchido em PT-BR>" \
  --base "$BASE_BRANCH" \
  --label "$AI_LABEL"
```

---

## 4. Acionar e Monitorar CI

Após abrir a PR, poste o comentário para acionar os testes:

```bash
gh pr comment <PR-URL> --body "/ok-to-test"
```

Aguarde a conclusão dos checks:

```bash
gh pr checks <PR-URL> --watch
```

### Se os testes passarem:
Retorne a URL da PR e encerre.

### Se os testes falharem:
1. Leia os logs para identificar os erros:
   ```bash
   gh run view --log-failed
   ```
2. Corrija os erros e faça novos commits atômicos seguindo a Seção 2.
3. Comente `/ok-to-test` novamente e aguarde.

> Tente corrigir no máximo **2 vezes**. Se o erro persistir após a segunda tentativa, informe o erro no terminal e retorne a URL da PR sem bloquear.

---

## 5. Atualizar Jira

Após a PR estar aberta e com CI verde (ou após as 2 tentativas):

1. Mova a task para `Revisao` usando `jira_get_issue_transitions` + `jira_transition_issue`.
2. Poste o link da PR como comentário na task usando `jira_add_comment`:

```
PR aberta: <PR-URL>
```

---

## 6. Limpeza do Worktree

Após a PR ser mergeada, remova o worktree para manter o ambiente limpo:

```bash
cd ..
git worktree remove <task-id>
```

Se o worktree tiver mudanças não commitadas, use `--force` apenas se tiver certeza de que não há trabalho a preservar.

---

## Regras

- Sempre trabalhe em worktree isolado — nunca commite direto na branch base.
- Nunca force push (`git push --force`) sem instrução explícita.
- O padrão de nome de branch é obrigatório: `<TASK-ID>/<descricao-kebab-case>`.
- O título da PR deve obrigatoriamente conter o ID da task em inglês: `<TASK-ID> | <descricao>`. Exemplo: `PROJ-123 | Add health check endpoint`.
- O body da PR deve ser em PT-BR.
- Resolva conflitos com merge — nunca rebase. Traga o que há de novo na branch base e ajuste o seu código.
- Faça push antes de abrir a PR.
- Limite de 2 tentativas de correção de CI — não entre em loop infinito.
- Detecte a branch base automaticamente — não assuma que é `main`.
- Verifique se o worktree já existe antes de criar um novo.
- Limpe o worktree após o merge da PR.
- Esta skill não implementa código — apenas versiona, abre PR e monitora CI.
