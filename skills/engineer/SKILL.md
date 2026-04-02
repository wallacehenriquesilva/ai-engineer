---
name: engineer
version: 1.1.0
description: >
  Busca a próxima task disponível na sprint ativa, avalia clareza,
  implementa, testa, abre PR e move para revisão.
  Lê configurações do CLAUDE.md do diretório atual.
  Se CLAUDE.md não existir, coleta as configurações e o gera automaticamente.
depends-on:
  - jira-integration
  - jira-task-clarity
  - git-workflow
  - init
  - execution-feedback
  - engineer-multi
  - slack-review
triggers:
  - user-command: /engineer
  - called-by: run
  - called-by: run-parallel
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
CI_MAX_RETRIES=$(grep "Máximo de tentativas:" CLAUDE.md | grep -oE '[0-9]+' | head -1 || echo "2")
SLACK_AUTO_REVIEW=$(grep "Slack Auto Review:" CLAUDE.md | awk '{print $NF}' || echo "false")
```

Se alguma variável essencial estiver vazia → encerre informando qual falta.
`$SLACK_AUTO_REVIEW` é opcional — se ausente, assume `false`.

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
18. Máximo de tentativas de CI (padrão: 2)
19. "Deseja notificar reviews no Slack automaticamente?" (S/n, padrão: n)
    Se sim:
    - 19a. ID do canal do Slack para reviews (ex: C0APYR0N7B4)
    - 19b. Mapa de usuários GitHub → Slack User ID (formato: `user.github: U0ABC123`, um por linha, ou Enter para pular)
    - 19c. Grupos de review por tipo (formato: `backend: @handle`, um por linha, ou Enter para pular. Use `default` como fallback)

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

Para as configurações de Slack:
- Se Slack habilitado → `Slack Auto Review: true`, preencha canal, user map e groups
- Se Slack desabilitado → `Slack Auto Review: false`, remova as seções de user map e groups do template

Para perguntas 12-19, use o padrão se vazio.

---

## Etapa 0.2 — Circuit Breaker

```bash
source ~/.ai-engineer/scripts/knowledge-client.sh
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

**CRITICAL:** A task retornada DEVE estar sem bloqueios ativos. O `jira-integration` (Seção A3) valida isso, mas confirme: se a task tem links do tipo "is blocked by" apontando para issues que **não** estão Done/Pronto → **rejeite e peça a próxima**. Nunca implemente uma task bloqueada.

**Apenas selecione a task — NÃO mova de status, NÃO mude para "Fazendo".** A task permanece em `To Do` até a Etapa 3.

---

## Etapa 2 — Avaliar Clareza

Use `jira-task-clarity`. Sem subtasks → avalie a task. Com subtasks → primeira não finalizada.

| Pontuação | Ação |
|---|---|
| >= $CONFIDENCE_THRESHOLD | Prossiga para Etapa 3 |
| < $CONFIDENCE_THRESHOLD | Vá para Etapa 2.1 |

Threshold rígido: abaixo = NÃO implementar, NÃO mover task.

---

## Etapa 2.1 — Verificar Comentários Anteriores

Clareza abaixo do threshold. Antes de comentar, busque os comentários da task no Jira e verifique se já existe um comentário do agente.

Identifique comentários do agente pelo marcador `[AI Engineer]` no corpo do comentário.

| Situação | Ação |
|---|---|
| Sem comentário `[AI Engineer]` | Vá para Etapa 2.2 — comentar pela primeira vez |
| Com comentário `[AI Engineer]` e **nenhuma resposta depois** (nenhum comentário de outro autor com data posterior) | Encerre silenciosamente — já está aguardando resposta. Não comente novamente. |
| Com comentário `[AI Engineer]` e **alguém respondeu depois** | Vá para Etapa 2.3 — reavaliar com contexto |

---

## Etapa 2.2 — Comentar Clareza

Primeiro comentário do agente nesta task. Comente no Jira com o marcador obrigatório:

```
[AI Engineer] Clareza: <PONTUAÇÃO>/18

<conteúdo baseado na pontuação>
```

| Pontuação | Conteúdo do comentário |
|---|---|
| 10 até threshold-1 | Liste as suposições que o agente faria para implementar. Peça confirmação a `$CLARITY_OWNERS`. |
| 6-9 | Liste as perguntas que precisam ser respondidas antes da implementação. Mencione `$CLARITY_OWNERS`. |

Encerre após comentar (task permanece em `To Do`).

---

## Etapa 2.3 — Reavaliar com Contexto

Alguém respondeu ao comentário do agente. Leia todas as respostas posteriores ao último `[AI Engineer]` e incorpore como contexto adicional à descrição da task.

Reavalie a clareza com `jira-task-clarity`, passando a descrição original + as respostas como contexto.

| Nova pontuação | Ação |
|---|---|
| >= $CONFIDENCE_THRESHOLD | Prossiga para Etapa 3 |
| < $CONFIDENCE_THRESHOLD | Comente novo follow-up com marcador `[AI Engineer]`, referenciando o que ainda falta. Encerre (task permanece em `To Do`). |

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
**2+ repos** → invoque a skill `engineer-multi` e siga o fluxo Multi-Repo. Após concluir, retome na Etapa 12.1.

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
source ~/.ai-engineer/scripts/execution-log.sh
exec_log_start "engineer" "<TASK-ID>" "<REPO-NAME>"
```

---

## Etapa 6.2 — Aprendizados

```bash
source ~/.ai-engineer/scripts/knowledge-client.sh
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

## Etapa 9.1 — Auto-review (Reality Check)

**Postura:** default é **NEEDS WORK**. Só prossiga se houver evidência concreta de que a implementação está correta. Não assuma que "compilou e testes passaram" é suficiente.

Revise sua própria implementação verificando:

| Critério | Como verificar | Bloqueante? |
|----------|---------------|-------------|
| Acceptance criteria atendidos | Compare cada critério da task com o código implementado. Liste: `✅ atendido` ou `❌ não atendido` | Sim |
| Testes cobrem os cenários | Verifique se há testes para happy path E edge cases descritos na task | Sim |
| Sem código morto ou debug | Grep por `fmt.Println`, `console.log`, `TODO`, `FIXME`, `HACK` nos arquivos alterados | Sim |
| Padrões do repo respeitados | Compare com código existente: naming, estrutura, error handling | Não |
| Sem regressões óbvias | Verifique se algum arquivo existente foi alterado de forma que quebre funcionalidade prévia | Sim |

### Resultado

- **Todos os critérios bloqueantes OK** → prossiga para Etapa 9.2
- **Algum critério bloqueante falhou** → corrija antes de prosseguir (máx 2 tentativas de auto-correção)
- **Falhou após 2 tentativas** → registre como falha e encerre (`exec_log_fail`)

```bash
# Exemplo de verificação automática de código morto
git diff --name-only HEAD | xargs grep -n 'fmt\.Println\|console\.log\|TODO\|FIXME\|HACK' || echo "CLEAN"
```

---

## Etapa 9.2 — Validação de Segurança

Valide a segurança do código implementado antes de prosseguir para commits.

### 1. Detectar linguagem

```bash
if [ -f "go.mod" ]; then
  LANG="go"
elif [ -f "package.json" ]; then
  LANG="js"
elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then
  LANG="java"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  LANG="python"
elif ls *.tf >/dev/null 2>&1; then
  LANG="terraform"
else
  LANG="unknown"
fi
```

### 2. Buscar skill de segurança instalada

Procure por skills de segurança na seguinte ordem de prioridade:

```bash
# 1. Skill específica para a linguagem: security-<lang>
SECURITY_SKILL=""
if [ -d "$HOME/.claude/skills/security-$LANG" ]; then
  SECURITY_SKILL="security-$LANG"
# 2. Skill genérica: security
elif [ -d "$HOME/.claude/skills/security" ]; then
  SECURITY_SKILL="security"
fi
```

### 3. Executar validação

**Se encontrou skill de segurança** (`$SECURITY_SKILL` não vazio):

Invoque a skill passando a lista de arquivos alterados:

```
/$SECURITY_SKILL <lista-de-arquivos-alterados>
```

A skill de segurança é responsável por analisar e retornar vulnerabilidades encontradas. Se retornar vulnerabilidades bloqueantes → corrija antes de prosseguir (máx 2 tentativas).

**Se NÃO encontrou skill de segurança** → execute checagem básica genérica:

Analise os arquivos alterados (`git diff --name-only`) procurando por:

| Risco | Pattern | Linguagens |
|-------|---------|------------|
| Secrets hardcoded | `password\s*=\s*["']`, `api_key\s*=\s*["']`, `secret\s*=\s*["']`, `token\s*=\s*["']` | Todas |
| SQL injection | Concatenação de strings em queries SQL (ex: `"SELECT.*" +`, `fmt.Sprintf("SELECT`) | Go, Java, Python, JS |
| Command injection | `exec(`, `os.system(`, `subprocess.call(.*shell=True`, `exec.Command(` com input não sanitizado | Python, Go, JS |
| XSS | `innerHTML`, `dangerouslySetInnerHTML`, `v-html` com input de usuário | JS |
| Credenciais em código | `.env` commitado, `AWS_SECRET`, `PRIVATE_KEY` | Todas |
| Permissões abertas | `0777`, `0666`, `*` em IAM policies | Todas, Terraform |

```bash
# Checagem genérica de secrets
git diff --name-only HEAD | xargs grep -inE \
  'password\s*=\s*["\x27]|api_key\s*=\s*["\x27]|secret\s*=\s*["\x27]|AWS_SECRET|PRIVATE_KEY' \
  || echo "CLEAN"
```

### 4. Resultado

| Resultado | Ação |
|-----------|------|
| Nenhuma vulnerabilidade encontrada | Prossiga para Etapa 10 |
| Vulnerabilidades encontradas | Corrija (máx 2 tentativas). Se não conseguir → registre como falha com detalhes do que foi encontrado |
| Skill de segurança não disponível + checagem básica limpa | Prossiga com aviso: **"Checagem básica de segurança OK. Para análise completa, instale uma skill `security-<lang>`."** |

---

## Etapa 10 — Commits

**Dry-run:** liste commits planejados. **Normal:** use `git-workflow` — Seção 2.

---

## Etapa 11 — PR

**Dry-run:** mostre título e body, pule para Etapa 14. **Normal:** use `git-workflow` — Seção 3.

Antes de criar a PR, leia o template e o exemplo:

```bash
cat ~/.claude/skills/git-workflow/templates/pr-template.md
cat ~/.claude/skills/git-workflow/examples/pr-example.md
```

**Obrigatório:** o body da PR deve seguir estritamente a estrutura do template. NÃO invente outro formato. Preencha os placeholders com dados da task e das mudanças implementadas.

---

## Etapa 12 — CI

**CRITICAL:** Nenhuma etapa posterior (custo, Slack, Jira) deve ser executada até que **TODOS os checks da PR estejam green**. Não basta um check específico passar — TODOS devem estar SUCCESS ou SKIPPED.

### 12.1 — Acionar CI

Leia a seção `## CI/CD Pipeline > ### Testes` do `CLAUDE.md` para determinar como acionar:

| Trigger no CLAUDE.md | Ação |
|---|---|
| `auto` | Não faça nada — CI roda sozinho. |
| `comment:<texto>` | `gh pr comment <PR-URL> --body "<texto>"` |
| `skip` | Pule toda a validação de CI e vá para Etapa 12.4 |

### 12.2 — Aguardar TODOS os checks ficarem green

Independente do tipo de validação configurada, **sempre** aguarde todos os checks da PR:

```bash
# Poll até todos os checks estarem concluídos (success, failure, ou skipped)
for i in $(seq 1 60); do
  PENDING=$(gh pr checks <PR-URL> --json state --jq '[.[] | select(.state == "PENDING" or .state == "QUEUED" or .state == "IN_PROGRESS")] | length' 2>/dev/null || echo "99")

  if [ "$PENDING" -eq 0 ]; then
    # Todos concluídos — verificar se algum falhou
    FAILED=$(gh pr checks <PR-URL> --json name,state --jq '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")] | length' 2>/dev/null || echo "0")

    if [ "$FAILED" -eq 0 ]; then
      echo "CI:ALL_GREEN"
      break
    else
      echo "CI:HAS_FAILURES"
      # Listar checks que falharam
      gh pr checks <PR-URL> --json name,state --jq '.[] | select(.state != "SUCCESS" and .state != "SKIPPED") | "\(.name): \(.state)"'
      break
    fi
  fi

  sleep 30
done
```

Se `CI:ALL_GREEN` → vá para Etapa 12.4 (custo).

### 12.3 — Corrigir falhas de CI

Se `CI:HAS_FAILURES`:

1. Identifique quais checks falharam e por quê:
   - **Checks de build/teste** → leia os logs, corrija o código, commit e push
   - **Checks de segurança (Aikido, Snyk, etc.)** → leia os comentários do bot na PR, corrija as vulnerabilidades reportadas
   - **SonarQube** → leia o comentário do bot, corrija code smells / bugs / vulnerabilidades
2. Após corrigir e push, reacione o CI se necessário:
   - Se trigger = `comment:<texto>` → poste o comentário novamente
   - Se trigger = `auto` → o push já reaciona
3. Volte para 12.2 (aguardar todos os checks)

**Máximo de tentativas:** `$CI_MAX_RETRIES` (lido do CLAUDE.md, padrão: 2). Se após `$CI_MAX_RETRIES` tentativas ainda houver checks falhando → registre como falha e encerre.

---

## Etapa 12.4 — Custo

```bash
source ~/.ai-engineer/scripts/calculate-cost.sh
```

---

## Etapa 12.5 — Registrar Sucesso

```bash
source ~/.ai-engineer/scripts/execution-log.sh
exec_log_end "PR aberta" "<PR-URL>" "$COST" "$INPUT" "$CACHE_WRITE" "$CACHE_READ" "$OUTPUT"
```

---

## Etapa 12.6 — Notificar Review no Slack

**CRITICAL:** Esta etapa só deve ser executada **após o CI estar 100% verde** (Etapa 12 concluída com sucesso). Se o CI falhou ou ainda está rodando, **NÃO envie a mensagem no Slack**. O time só deve ser notificado quando a PR estiver pronta para revisão.

Antes de enviar, valide:

```bash
# Confirmar que todos os checks passaram
gh pr checks <PR-URL> --json name,state --jq '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")] | length'
```

Se o resultado for `> 0` → **NÃO envie**. Aguarde ou corrija primeiro.

Se `$SLACK_AUTO_REVIEW` = `true` **E** CI verde:

```
/slack-review request <PR-URL>
```

A skill `slack-review` irá:
- Enviar mensagem no canal configurado (`Slack Review Channel`)
- Mencionar o grupo de review correto (`Slack Review Groups`) baseado no tipo de mudança
- Verificar duplicatas antes de enviar
- Retornar o `ts` (timestamp) da mensagem enviada

Após enviar, salve o `ts` no work queue para uso futuro em replies na thread:

```bash
source ~/.ai-engineer/scripts/work-queue.sh
wq_set_slack_ts "$TASK_ID" "$REPO_NAME" "<ts retornado pelo slack-review>"
```

Se `$SLACK_AUTO_REVIEW` = `false` → pule esta etapa.

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
- Máximo `$CI_MAX_RETRIES` tentativas de CI (padrão: 2)
- Clareza < threshold = NÃO implementar
- Budget: verifique após Etapas 8 e 9
- Circuit breaker: 3+ falhas = parar (exceto --force)
- Dry-run: NUNCA execute ações destrutivas
- Multi-repo: invoque a skill `engineer-multi`
