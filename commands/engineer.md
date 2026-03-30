---
description: >
  Busca a próxima task disponível na sprint ativa, avalia clareza,
  implementa, testa, abre PR e move para revisão.
  Lê configurações do CLAUDE.md do diretório atual.
  Se CLAUDE.md não existir, coleta as configurações e o gera automaticamente.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - TaskCreate
  - TaskUpdate
  - mcp__mcp-atlassian__jira_*
  - mcp__github__*
---

# engineer: Implementação Automática de Task

Execute as etapas abaixo em ordem.

## Flags

- `--dry-run` → Simula sem executar ações destrutivas (branch, commit, PR, Jira).
- `--budget <valor>` → Limite de custo em USD (sobrescreve CLAUDE.md).
- `--force` → Ignora circuit breaker.

Guarde `$DRY_RUN` (true/false) para verificar antes de ações destrutivas.

---

## Etapa 0 — Pré-condições

```bash
gh auth status 2>&1 | head -3
command -v jq >/dev/null && echo "jq OK" || echo "jq NOT FOUND"
```

Se `gh` falhar → encerre. Se `jq` falhar → prossiga sem cálculo de custo.

Verifique se `.mcp.json` existe no diretório atual:

```bash
test -f .mcp.json && echo "mcp-ok" || echo "mcp-missing"
```

Se `mcp-missing` → verifique se as credenciais existem em `~/.ai-engineer/.env`:

```bash
test -f ~/.ai-engineer/.env && grep -q "JIRA_API_TOKEN" ~/.ai-engineer/.env && echo "env-ok" || echo "env-missing"
```

Se `env-ok` → gere `.mcp.json` lendo as variáveis do `.env`:

```bash
source ~/.ai-engineer/.env
```

Crie `.mcp.json` com o conteúdo:

```json
{
  "mcpServers": {
    "github": {
      "type": "stdio",
      "command": "gh",
      "args": ["mcp"]
    },
    "mcp-atlassian": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "JIRA_URL": "$JIRA_URL",
        "JIRA_USERNAME": "$JIRA_USERNAME",
        "JIRA_API_TOKEN": "$JIRA_API_TOKEN",
        "CONFLUENCE_URL": "$CONFLUENCE_URL",
        "CONFLUENCE_USERNAME": "$JIRA_USERNAME",
        "CONFLUENCE_API_TOKEN": "$JIRA_API_TOKEN"
      }
    }
  }
}
```

Substitua as variáveis `$JIRA_URL`, `$JIRA_USERNAME`, `$JIRA_API_TOKEN` e `$CONFLUENCE_URL` pelos valores reais lidos do `.env`. Após criar, informe ao usuário que é necessário reiniciar o Claude Code para carregar os MCPs e **encerre a execução**.

Se `env-missing` → encerre com erro:
> **Erro:** `.mcp.json` não encontrado e credenciais Jira não configuradas. Execute o instalador: `curl -fsSL https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/install.sh -o /tmp/install.sh && bash /tmp/install.sh`

---

## Etapa 0.1 — Configurações

```bash
test -f CLAUDE.md && echo "exists" || echo "missing"
```

**Se existir:** extraia variáveis:

```bash
JIRA_BOARD=$(grep "Jira Board:" CLAUDE.md | awk '{print $NF}')
JIRA_PROJECT=$(grep "Jira Project:" CLAUDE.md | awk '{print $NF}')
AI_LABEL=$(grep "Label IA:" CLAUDE.md | awk '{print $NF}')
CLARITY_OWNERS=$(grep -A1 "Responsáveis por clareza" CLAUDE.md | tail -1 | xargs)
GITHUB_ORG=$(grep "GitHub Org:" CLAUDE.md | awk '{print $NF}')
GITHUB_TEAM=$(grep "GitHub Team:" CLAUDE.md | awk '{print $NF}')
SONAR_BOT=$(grep "Bot do SonarQube:" CLAUDE.md | awk '{print $NF}')
BUDGET_LIMIT=$(grep "Budget limit:" CLAUDE.md | grep -oE '[0-9]+\.[0-9]+' || echo "5.00")
CONFIDENCE_THRESHOLD=$(grep "Confidence threshold:" CLAUDE.md | grep -oE '[0-9]+' | head -1 || echo "15")
CIRCUIT_BREAKER_THRESHOLD=$(grep "Circuit breaker:" CLAUDE.md | grep -oE '[0-9]+' | head -1 || echo "3")
```

Se alguma variável essencial estiver vazia → encerre informando qual falta.

**Se não existir:**

Primeiro, verifique se o template existe:

```bash
test -f ~/.ai-engineer/docs/CLAUDE.md.template && echo "template-ok" || echo "template-missing"
```

Se `template-missing` → encerre com erro:
> **Erro:** Template não encontrado em `~/.ai-engineer/docs/CLAUDE.md.template`. Execute o instalador novamente: `curl -fsSL https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/install.sh -o /tmp/install.sh && bash /tmp/install.sh --skills`

Se `template-ok` → pergunte uma de cada vez:

1. Nome do time
2. ID do board do Jira
3. Chave do projeto no Jira
4. Label que marca tasks para IA (padrão: AI)
5. Responsáveis para clareza
6. Organização no GitHub
7. Handle do time de revisão no GitHub
8. Login do bot do SonarQube (ou Enter se não usa)
9. "Como o CI de testes é acionado?" Ofereça presets:
   - **A) Automático** — CI roda sozinho ao abrir PR (padrão)
   - **B) Comentário** — precisa postar um comentário na PR (ex: `/ok-to-test`)
   - **C) Não tem** — pular
   Se B: pergunte qual comentário.
10. "Como o deploy em sandbox é acionado?" (mesmos presets A/B/C, default: C-skip)
11. "Como o deploy em homolog é acionado?" (mesmos presets, default: C-skip)
12. Domínio de sandbox (ex: dev.mycompany.local — ou Enter para pular)
13. Domínio de homologação (ex: hml.mycompany.local — ou Enter para pular)
14. Domínio de produção (ex: prod.mycompany.local — ou Enter para pular)
15. Limite de custo USD por execução (padrão: 5.00)
16. Pontuação mínima de clareza (padrão: 15)
17. Falhas para circuit breaker (padrão: 3)

Gere o `CLAUDE.md` lendo o template de `~/.ai-engineer/docs/CLAUDE.md.template` e substituindo os placeholders pelas respostas coletadas. **NÃO invente um formato próprio — use estritamente o template.**

Para os triggers de pipeline, converta as respostas nos formatos:
- Automático → `auto`
- Comentário X → `comment:X`
- Não tem → `skip`

Para validação, use os defaults:
- Testes com SonarQube → `sonarqube:<bot-login>`
- Testes sem SonarQube → `checks:*`
- Sandbox/Homolog → `checks:<nome-do-check-pattern>`
- Produção → `gh-runs:prod|production|deploy`

Para perguntas 12-17, use o padrão se vazio.

---

## Etapa 0.2 — Circuit Breaker

```bash
source scripts/knowledge-client.sh
RECENT=$(kc_exec_list 5 2>/dev/null || echo "[]")
CONSECUTIVE_FAILURES=$(echo "$RECENT" | jq '[.[] | select(.status == "failure")] | length' 2>/dev/null || echo "0")
```

Se `>= $CIRCUIT_BREAKER_THRESHOLD` e sem `--force` → encerre listando os motivos recentes. Se knowledge-service indisponível → pule.

---

## Etapa 0.3 — Budget

Se `--budget <valor>` foi passado, use-o. Senão use `$BUDGET_LIMIT`. Verificar custo após Etapas 8 e 9.

---

## Etapa 1 — Buscar Task

Use `jira-integration` com board `$JIRA_BOARD`, label `$AI_LABEL`, status `To Do`. Se nenhuma → encerre.

**Apenas selecione a task — NÃO mova de status, NÃO mude para "Fazendo".** A task permanece em `To Do` até a Etapa 3.

---

## Etapa 2 — Avaliar Clareza

Use `jira-task-clarity`. Sem subtasks → avalie a task. Com subtasks → primeira não finalizada.

| Pontuação | Ação |
|---|---|
| >= $CONFIDENCE_THRESHOLD | Prossiga para Etapa 3 |
| 10 até threshold-1 | Comente suposições no Jira, encerre (task permanece em `To Do`) |
| 6-9 | Comente perguntas no Jira, encerre (task permanece em `To Do`) |

Threshold rígido: abaixo = NÃO implementar, NÃO mover task.

---

## Etapa 3 — Definir Alvo

**Só execute esta etapa se a clareza passou na Etapa 2 (>= $CONFIDENCE_THRESHOLD).**

Sem subtasks → mova task para `Fazendo`. Com subtasks → filtre por `$AI_LABEL`, selecione primeira válida, mova ambas.

---

## Etapa 4 — Localizar Repos

```bash
find . -maxdepth 2 -type d -name "<nome-do-repo>"
```

Não encontrado → clone: `gh repo clone $GITHUB_ORG/<repo>`.

**1 repo** → prossiga para Etapa 5.
**2+ repos** → leia `commands/engineer-multi.md` e siga o fluxo Multi-Repo. Após concluir, retome na Etapa 12.1.

---

## Etapa 5 — CLAUDE.md do Repo e Worktree

Verifique `CLAUDE.md` no repo. Se não existir → execute `/init`.

**Dry-run:** registre `[DRY-RUN] Criaria worktree: <TASK-ID>/<descricao>`.
**Normal:** `/worktree create <TASK-ID>/<descricao-kebab-case>`

---

## Etapa 6 — DORA Metrics

**Dry-run:** pule. **Normal:**

```bash
git commit -m 'chore: initial commit' --allow-empty
git push origin <branch>
```

---

## Etapa 6.1 — Registrar Execução

```bash
source scripts/execution-log.sh
exec_log_start "engineer" "<TASK-ID>" "<REPO-NAME>"
```

---

## Etapa 6.2 — Aprendizados

```bash
source scripts/knowledge-client.sh
REPO_LEARNINGS=$(kc_learning_search "<resumo da task>" "<REPO-NAME>" 5 2>/dev/null || echo "[]")
```

Se houver → inclua como avisos no plano da Etapa 7.

---

## Etapa 7 — Planejar

Examine o repo. Salve plano em `.claude/plans/plan-<TASK-ID>.md`: resumo, componentes reutilizados, novos, ordem, avisos de aprendizados.

---

## Etapa 8 — Implementar

**Dry-run:** gere código sem escrever em disco, mostre como diff, pule para Etapa 14.
**Normal:** siga o plano. Verifique budget após implementar.

---

## Etapa 9 — Testar

Execute testes. Corrija falhas. Verifique budget após testes.

---

## Etapa 10 — Commits

**Dry-run:** liste commits planejados. **Normal:** use `git-workflow` — Seção 2.

---

## Etapa 11 — PR

**Dry-run:** mostre título e body, pule para Etapa 14. **Normal:** use `git-workflow` — Seção 3. Use o template em `skills/git-workflow/templates/pr-template.md`.

---

## Etapa 12 — CI

```bash
gh pr edit <PR-URL> --add-label "ai-generated"
```

Leia a seção `## CI/CD Pipeline > ### Testes` do `CLAUDE.md` para determinar como acionar e validar o CI:

| Trigger no CLAUDE.md | Ação |
|---|---|
| `auto` | Não faça nada — CI roda sozinho. Apenas aguarde. |
| `comment:<texto>` | `gh pr comment <PR-URL> --body "<texto>"` |
| `skip` | Pule a validação de CI |

| Validação no CLAUDE.md | Como verificar |
|---|---|
| `sonarqube:<bot>` | Poll comentários da PR: `gh pr view <PR-URL> --comments --json comments \| jq '.comments[] \| select(.author.login == "<bot>")'` até encontrar "Quality Gate passed/failed" |
| `checks:<pattern>` | `gh pr checks <PR-URL> --watch` ou poll por checks com nome matching `<pattern>` |
| `checks:*` | `gh pr checks <PR-URL> --watch` (todos os checks) |

Use `git-workflow` — Seção 4 para correções (máx 2 tentativas, lido do CLAUDE.md).

---

## Etapa 12.1 — Custo

```bash
source scripts/calculate-cost.sh
```

---

## Etapa 12.2 — Registrar Sucesso

```bash
source scripts/execution-log.sh
exec_log_end "PR aberta" "<PR-URL>" "$COST" "$INPUT" "$CACHE_WRITE" "$CACHE_READ" "$OUTPUT"
```

---

## Etapa 13 — Jira

Mova para `Em Revisão`. Comente com PR-URL e custo. Com subtasks: mova subtask; se última → mova mãe também.

---

## Etapa 14 — Confirmação

**Dry-run:** exiba task, clareza, repo, branch/arquivos/commits/PR que seriam criados, custo da simulação.
**Normal:** exiba task, branch, PR-URL, status CI, custo, tokens, status Jira.

---

## Em Caso de Falha

1. `exec_log_fail <STEP> "<motivo>" "<PR-URL>"`
2. Registre aprendizado via `execution-feedback` (Seção A)
3. Comente na task mencionando `$CLARITY_OWNERS`
4. Mova task de `Fazendo` para `To Do`
5. Preserve worktree

---

## Regras

- Nunca pule DORA (Etapa 6) em modo normal
- Nunca commite na `main`
- Nunca force push
- Reutilize código existente
- Máximo 2 tentativas de CI
- Clareza < threshold = NÃO implementar
- Budget: verifique após Etapas 8 e 9
- Circuit breaker: 3+ falhas = parar (exceto --force)
- Dry-run: NUNCA execute ações destrutivas
- Multi-repo: leia `commands/engineer-multi.md`
