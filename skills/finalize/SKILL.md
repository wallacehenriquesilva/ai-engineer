---
name: finalize
version: 1.0.0
description: >
  Finaliza o ciclo de uma task aprovada: valida aprovação da PR, envia para sandbox
  e homolog, gera evidências de funcionamento, move a task no Jira e acompanha
  o deploy em produção após o merge.
  Lê configurações do CLAUDE.md do diretório atual. Uso: /finalize <PR-URL>
depends-on:
  - git-workflow
  - slack-review
triggers:
  - user-command: /finalize
  - called-by: run
allowed-tools:
  - Bash
  - Read
  - Write
  - mcp__mcp-atlassian__jira_*
  - mcp__github__*
  - mcp__playwright__*
---

# finalize: Finalização e Deploy da Task

## Etapa 0 — Carregar Configurações

```bash
test -f CLAUDE.md && echo "exists" || echo "missing"
```

Se não existir: **"CLAUDE.md não encontrado. Execute /engineer primeiro."**

```bash
GITHUB_ORG=$(grep "GitHub Org:" CLAUDE.md | awk '{print $NF}')
JIRA_PROJECT=$(grep "Jira Project:" CLAUDE.md | awk '{print $NF}')
CLARITY_OWNERS=$(grep -A1 "Responsáveis por clareza" CLAUDE.md | tail -1 | xargs)
FIRST_OWNER=$(echo "$CLARITY_OWNERS" | cut -d',' -f1 | xargs)
SANDBOX_DOMAIN=$(grep "Sandbox:" CLAUDE.md | grep -oE '<service>\.[^ ]*' | sed 's/<service>\.//' || echo "")
HOMOLOG_DOMAIN=$(grep "Homologação:" CLAUDE.md | grep -oE '<service>\.[^ ]*' | sed 's/<service>\.//' || echo "")
PROD_DOMAIN=$(grep "Produção:" CLAUDE.md | grep -oE '<service>\.[^ ]*' | sed 's/<service>\.//' || echo "")
SLACK_AUTO_REVIEW=$(grep "Slack Auto Review:" CLAUDE.md | awk '{print $NF}' || echo "false")
```

---

## Etapa 1 — Validar PR e Aprovação

```bash
gh pr view <PR-URL> --json title,body,headRefName,state,reviews,mergeStateStatus
```

Valide:
1. PR deve estar **aberta** (`state: OPEN`) — se merged/closed: **"PR já encerrada."**
2. Ao menos **uma aprovação** (`state: APPROVED`):

```bash
gh pr view <PR-URL> --json reviews \
  | jq -r '.reviews[] | select(.state == "APPROVED") | .author.login'
```

Se sem aprovação: **"PR ainda não aprovada. Aguarde ao menos uma aprovação."**

Extraia:
- **Chave da task Jira** — do body da PR
- **Nome do serviço** — do nome do repo na URL da PR
- **Tipo de repo** — termina com `-infra`? → Terraform. Demais → serviço.
- **É frontend?** — detecte pelo repo: `package.json` com React/Next.js/Vue → `IS_FRONTEND=true`
- **Endpoint da task** — leia a descrição via `jira_get_issue`
- **URL da tela** (se frontend) — extraia da descrição da task ou dos critérios de aceite a URL/rota que foi alterada

```bash
# Detectar se é frontend
IS_FRONTEND=false
if [ -f "package.json" ]; then
  grep -qE '"react"|"next"|"vue"|"angular"' package.json && IS_FRONTEND=true
fi
```

### Template de evidências

Use o template correto para gerar evidências padronizadas:
- Backend → [templates/evidence-backend.md](templates/evidence-backend.md)
- Frontend → [templates/evidence-frontend.md](templates/evidence-frontend.md)

Preencha os placeholders com os dados reais de cada ambiente. Omita seções de ambientes com trigger `skip`.

---

## Etapa 2 — Deploy em Sandbox

Leia `## CI/CD Pipeline > ### Sandbox` do CLAUDE.md.

Se trigger = `skip` → pule para Etapa 4.

Se trigger = `comment:<texto>`:
```bash
gh pr comment <PR-URL> --body "<texto>"
```

Se trigger = `auto` → não faça nada, apenas aguarde.

Se trigger = `merge:<branch>` → merge a PR para a branch alvo e aguarde.

Validação: execute conforme o campo `Validação` do CLAUDE.md (ver tabela de validações na Etapa 12 do `/engineer`). Timeout conforme configurado.

Se falhar: **"Deploy em sandbox falhou. Verifique os logs antes de prosseguir."**

---

## Etapa 3 — Validar Sandbox

Se `$SANDBOX_DOMAIN` está vazio → pule.

### Backend (`IS_FRONTEND=false`):

```bash
curl -si -X <METHOD> \
  "http://<service-name>.$SANDBOX_DOMAIN/<endpoint>" \
  -H "Content-Type: application/json" \
  -d '<payload-se-necessario>'
```

Status >= 400 → **"Serviço não respondeu corretamente em sandbox."**

### Frontend (`IS_FRONTEND=true`):

Use Playwright para abrir a URL alterada e tirar screenshot:

1. Navegue até `http://<service-name>.$SANDBOX_DOMAIN/<rota-da-tela>`
2. Aguarde a página carregar completamente (networkidle)
3. Tire screenshot da página inteira
4. Salve em `.claude/evidence/screenshot-<TASK-ID>-sandbox.png`
5. Se a página retornar erro visível (tela de erro, 404, 500) → **"Frontend não renderizou corretamente em sandbox."**

---

## Etapa 4 — Deploy em Homolog

Leia `## CI/CD Pipeline > ### Homolog` do CLAUDE.md.

Se trigger = `skip` → pule para Etapa 6.

Mesma lógica da Etapa 2: execute trigger, aguarde validação conforme configurado.

Se falhar: **"Deploy em homolog falhou."**

---

## Etapa 5 — Validar Homolog e Gerar Evidências

Se `$HOMOLOG_DOMAIN` está vazio → pule a validação de endpoint mas gere evidências do CI.

### Backend (`IS_FRONTEND=false`):

Se `$HOMOLOG_DOMAIN` está preenchido:

```bash
curl -si -X <METHOD> \
  "http://<service-name>.$HOMOLOG_DOMAIN/<endpoint>" \
  -H "Content-Type: application/json" \
  -d '<payload-se-necessario>'
```

Status >= 400 → **"Serviço não respondeu corretamente em homolog."**

Salve evidências em `.claude/evidence/evidence-<TASK-ID>.md` com: serviço, ambiente, data, request, response e resultado.

### Frontend (`IS_FRONTEND=true`):

Se `$HOMOLOG_DOMAIN` está preenchido:

1. Navegue até `http://<service-name>.$HOMOLOG_DOMAIN/<rota-da-tela>`
2. Aguarde a página carregar completamente (networkidle)
3. Tire screenshot da página inteira
4. Salve em `.claude/evidence/screenshot-<TASK-ID>-homolog.png`
5. Se a task especificar múltiplas rotas ou estados, tire screenshot de cada um
6. Se a página retornar erro visível → **"Frontend não renderizou corretamente em homolog."**

Salve evidências em `.claude/evidence/evidence-<TASK-ID>.md` incluindo:
- Screenshots tirados (paths)
- URL de cada screenshot
- Status visual (renderizou corretamente ou não)

---

## Etapa 6 — Atualizar Jira

Poste o relatório de evidências como comentário na task via `jira_add_comment`.

Mova a task (ou subtask) para `Done` / `Pronto` via `jira_get_issue_transitions` + `jira_transition_issue`.

Se for subtask, verifique as demais:
- Todas em `Done`/`Pronto` → mova task mãe para `Done` e comente nela também.
- Ainda há pendentes → task mãe permanece como está.

---

## Etapa 7 — Merge da PR

A PR está aprovada por um humano, validada em sandbox e homolog. Merge automático.

```bash
gh pr merge <PR-URL> --squash --delete-branch
```

### Notificar merge no Slack

Se `$SLACK_AUTO_REVIEW` = `true`:

```
/slack-review reply <PR-URL>
```

A skill `slack-review` detecta automaticamente que a PR está merged e adiciona o indicador `:merged:` na thread original.

### Limpar worktree

Após merge confirmado, remova a worktree da task para não acumular:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_PATH="$REPO_ROOT/worktrees/<TASK-ID>"

if [ -d "$WORKTREE_PATH" ]; then
  git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || true
fi
```

---

## Etapa 8 — Aguardar Deploy em Produção

Leia `## CI/CD Pipeline > ### Produção` do CLAUDE.md.

Se trigger = `skip` → pule para Etapa 9.

Se trigger = `auto` → deploy ocorre automaticamente após merge. Aguarde validação.

Validação conforme configurado:
- `gh-runs:<pattern>` → poll `gh run list --repo $GITHUB_ORG/<repo> --branch main` filtrando por pattern
- `checks:<pattern>` → poll checks da PR

Timeout conforme configurado no CLAUDE.md.

Se não monitorável: **"Verifique manualmente o deploy em produção."**

---

## Etapa 8.1 — Rollback Automatizado (se produção falhar)

Se o deploy em produção falhar (`PROD:FAILED`):

### 1. Executar rollback automaticamente

```bash
REVERT_BRANCH="revert/<TASK-ID>"
git checkout main
git pull origin main
git checkout -b "$REVERT_BRANCH"
git revert --no-edit HEAD
git push -u origin "$REVERT_BRANCH"

gh pr create \
  --title "revert: rollback <TASK-ID>" \
  --body "Rollback automático — deploy em produção falhou." \
  --base main \
  --label "rollback"

gh pr merge --squash --delete-branch
```

### 2. Aguardar deploy do rollback

Repita o polling da Etapa 8 para confirmar que o rollback subiu.

### 3. Notificar no Jira

Comente na task via `jira_add_comment`:

```
⚠️ Rollback executado em produção.

Motivo: deploy falhou após merge.
PR original: <PR-URL>
PR de rollback: <REVERT-PR-URL>

Requer investigação antes de nova tentativa.
```

Mova a task de volta para `Fazendo`.

---

## Etapa 9 — Validar Produção e Gerar Evidências

Se `$PROD_DOMAIN` está vazio → pule a validação de endpoint.

### Backend (`IS_FRONTEND=false`):

Se `$PROD_DOMAIN` está preenchido:

```bash
curl -si -X <METHOD> \
  "http://<service-name>.$PROD_DOMAIN/<endpoint>" \
  -H "Content-Type: application/json" \
  -d '<payload-se-necessario>'
```

Salve evidências em `.claude/evidence/evidence-<TASK-ID>-prod.md`.

### Frontend (`IS_FRONTEND=true`):

Se `$PROD_DOMAIN` está preenchido:

1. Navegue até `http://<service-name>.$PROD_DOMAIN/<rota-da-tela>`
2. Aguarde a página carregar completamente (networkidle)
3. Tire screenshot da página inteira
4. Salve em `.claude/evidence/screenshot-<TASK-ID>-prod.png`
5. Se a task especificar múltiplas rotas ou estados, tire screenshot de cada um

Salve evidências em `.claude/evidence/evidence-<TASK-ID>-prod.md` incluindo:
- Screenshots tirados (paths)
- URL de cada screenshot
- Status visual (renderizou corretamente ou não)

### Postar evidências no Jira

Poste o relatório de evidências como comentário na task via `jira_add_comment`. Para tasks de frontend, mencione os screenshots e inclua os links/paths das imagens.

---

## Etapa 10 — Confirmação Final

```
## ✅ Task finalizada

- **Task:** <KEY> — <summary>
- **PR:** <PR-URL> (merged)
- **Sandbox:** ✅ validado
- **Homolog:** ✅ validado
- **Produção:** ✅ validado
- **Evidências:** .claude/evidence/evidence-<TASK-ID>.md
- **Screenshots:** <lista de screenshots, se frontend>
- **Status Jira:** Done
```

---

## Em Caso de Falha

Se qualquer deploy falhar de forma irrecuperável:

1. Comente na task:

```
<FIRST_OWNER>

O processo de deploy falhou na Etapa <N>.

Motivo: <descrição breve>
PR: <PR-URL>
Ambiente: <sandbox | homolog | produção>

Requer intervenção manual.
```

2. Não faça merge se a falha ocorreu antes da Etapa 7.
3. Encerre com o resumo de falha.

---

## Regras Gerais

- Etapas com trigger `skip` são puladas — respeite a configuração do time.
- Nunca prossiga para a próxima etapa se a atual falhou (exceto se `skip`).
- Nunca valide produção sem o merge concluído.
- Se produção falhar, execute rollback automaticamente.
- Sempre gere evidências antes de atualizar o Jira.
- Nunca force push.
- Leia sempre o `CLAUDE.md` — nunca use valores hardcoded.
