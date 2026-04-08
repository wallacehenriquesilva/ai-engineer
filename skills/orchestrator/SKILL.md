---
name: orchestrator
version: 1.0.0
description: >
  Analisa uma task do Jira e decide qual workflow executar baseado em
  tipo, labels, prioridade, repos envolvidos e runbooks disponíveis.
  Roteamento inteligente entre engineer, engineer-multi, hotfix e refactoring.
  Uso: /orchestrator <TASK-ID>
depends-on:
  - jira-integration
  - engineer
  - engineer-multi
  - execution-feedback
triggers:
  - called-by: run-queue
  - called-by: run
  - user-command: /orchestrator
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
  - Skill
  - mcp__mcp-atlassian__jira_get_issue
---

# orchestrator: Roteamento Inteligente de Tasks

Analisa a task e decide qual workflow seguir antes de invocar o engineer.

## Flags

- `<TASK-ID>` → ID da task no Jira (opcional — se não fornecido, busca a próxima disponível)
- `--repo <path>` → Caminho do repositório alvo (opcional, detectado automaticamente)

---

## Etapa 0 — Obter Task

### Se `<TASK-ID>` foi fornecido:

Use o ID diretamente. Vá para Etapa 1.

### Se nenhum TASK-ID foi fornecido:

Busque a próxima task disponível no Jira (mesma lógica da Etapa 1 do engineer):

```bash
# Carregar configurações do CLAUDE.md
JIRA_BOARD=$(grep "Jira Board:" CLAUDE.md | awk '{print $NF}')
AI_LABEL=$(grep "Label IA:" CLAUDE.md | awk '{print $NF}')
```

Use `jira-integration` com board `$JIRA_BOARD`, label `$AI_LABEL`, status `To Do`.

**CRITICAL — HARD STOP:** Se nenhuma task for encontrada em "To Do"/"A Fazer" na sprint ativa, **ENCERRE IMEDIATAMENTE**. Exiba: **"Nenhuma task disponível na sprint. Encerrando."** e pare. NÃO busque no backlog, NÃO amplie a busca, NÃO remova filtros, NÃO tente sem sprint, NÃO tente outros status. Zero tasks = zero trabalho. Ir ao backlog sem autorização humana é proibido.

**CRITICAL:** A task retornada DEVE estar sem bloqueios ativos. Se a task tem links do tipo "is blocked by" apontando para issues que **não** estão Done/Pronto → rejeite e peça a próxima. Nunca rotee uma task bloqueada.

**Apenas selecione a task — NÃO mova de status.** A task permanece em `To Do` até o engineer movê-la.

Guarde `$TASK_ID` com o ID da task selecionada.

---

## Etapa 1 — Coletar Sinais da Task

### 1.1 — Buscar dados do Jira

Use o MCP do Jira para buscar os detalhes da task:

```
mcp__mcp-atlassian__jira_get_issue(issue_key: "$TASK_ID")
```

Extraia:
- `labels` → lista de labels (ex: ["AI", "hotfix"])
- `priority` → prioridade (ex: "Highest", "High", "Medium", "Low")
- `summary` → título da task
- `description` → descrição completa
- `issueType` → tipo (Bug, Story, Task, Sub-task)
- `components` → componentes associados
- `subtasks` → lista de subtasks (se houver)

### 1.2 — Detectar repos envolvidos

Analise a descrição e o summary da task para identificar repos:

1. Nomes de serviços mencionados (ex: "martech-worker", "notification-hub")
2. Referências a infra (ex: "SNS", "SQS", "Terraform", "IAM")
3. Se o diretório atual é um repo específico, use como repo primário

Se estiver num diretório de repo, detecte o tipo:

```bash
# Detectar tipo do repo
if [ -f go.mod ]; then
  REPO_TYPE="go"
elif [ -f package.json ]; then
  REPO_TYPE="node"
  if grep -q '"next"' package.json 2>/dev/null; then
    REPO_TYPE="frontend"
  fi
elif [ -f pom.xml ]; then
  REPO_TYPE="java"
elif ls *.tf 1>/dev/null 2>&1; then
  REPO_TYPE="terraform"
fi

# Detectar se é repo de infra
REPO_NAME=$(basename "$PWD")
if [[ "$REPO_NAME" == *-infra ]]; then
  REPO_TYPE="terraform"
fi
```

### 1.3 — Verificar histórico de falhas

Consulte aprendizados recentes do repo:

```bash
source ~/.ai-engineer/scripts/knowledge-client.sh 2>/dev/null
kc_learning_search "$REPO_NAME" 2>/dev/null || echo "knowledge-service indisponível"
```

Se houver falhas recentes (últimos 7 dias), marque `HAS_RECENT_FAILURES=true`.

---

## Etapa 2 — Classificar Tipo da Task

Aplique as regras de classificação **na ordem de prioridade** (primeira que bater, ganha):

### Regra 1: Hotfix
```
SE labels contém "hotfix" OU labels contém "incident"
   OU priority IN ("Highest", "P0", "P1")
   OU issueType = "Bug" E priority IN ("High", "P1"):
  TIPO = "hotfix"
```

### Regra 2: Multi-Repo
```
SE descrição menciona 2+ repos distintos
   OU descrição menciona "infra" E repo atual NÃO é -infra
   OU task tem subtasks em repos diferentes:
  TIPO = "multi-repo"
```

### Regra 3: Infra-Only
```
SE REPO_TYPE = "terraform"
   OU labels contém "infra"
   OU descrição é exclusivamente sobre SNS/SQS/IAM/Terraform:
  TIPO = "infra"
```

### Regra 4: Refactoring Grande
```
SE labels contém "refactoring" OU labels contém "tech-debt"
   OU summary contém "refat" OU "migra" OU "renomear":
  TIPO = "refactoring"
```

### Regra 5: Nova Integração
```
SE labels contém "integration" OU labels contém "new-consumer"
   OU descrição menciona "novo consumer" OU "novo tópico" OU "webhook"
   OU descrição menciona API externa (Braze, Segment, Salesforce, Twilio):
  TIPO = "integration"
```

### Regra 6: Default
```
TIPO = "feature"
```

---

## Etapa 3 — Selecionar Runbook

Leia os runbooks disponíveis e faça match pelo frontmatter:

```bash
for runbook in ~/.ai-engineer/docs/runbooks/*.md; do
  # Ler frontmatter e comparar triggers com sinais coletados
done
```

**Fallback:** se o projeto tiver `docs/runbooks/` próprio, verifique lá também.

O match funciona assim:
- Se `triggers.labels` tem interseção com as labels da task → match
- Se `triggers.priority` tem interseção com a prioridade → match
- Se `triggers.keywords` aparece na descrição/summary → match
- Se `triggers.multi_repo = true` e TIPO = "multi-repo" ou "integration" → match

Se houver match, guarde o caminho do runbook em `$RUNBOOK_PATH`.

---

## Etapa 4 — Montar Plano de Execução

Baseado no TIPO, monte o plano:

### Hotfix
```
SKILL = "engineer"
FLAGS = "--skip-clarity --fast-ci --min-reviewers 1"
RUNBOOK = "docs/runbooks/hotfix-p0.md"
BRANCH_PREFIX = "hotfix/"
```

### Multi-Repo
```
SKILL = "engineer-multi"
FLAGS = ""
RUNBOOK = "$RUNBOOK_PATH"  # pode ser new-integration.md se aplicável
```

### Infra-Only
```
SKILL = "engineer"
FLAGS = "--skip-app-tests"
RUNBOOK = "$RUNBOOK_PATH"
```

### Refactoring
```
SKILL = "engineer"
FLAGS = "--runbook docs/runbooks/large-refactoring.md"
RUNBOOK = "docs/runbooks/large-refactoring.md"
```

### Integration
```
# Verificar se precisa de infra + app
SE descrição menciona infra E repo atual NÃO é -infra:
  SKILL = "engineer-multi"
SENÃO:
  SKILL = "engineer"
FLAGS = "--runbook docs/runbooks/new-integration.md"
RUNBOOK = "docs/runbooks/new-integration.md"
```

### Feature (default)
```
SKILL = "engineer"
FLAGS = ""
RUNBOOK = ""
```

### Ajustes adicionais

```
SE HAS_RECENT_FAILURES:
  FLAGS += " --consult-learnings"

SE repo atual não tem CLAUDE.md:
  # Invocar /init antes
  INIT_FIRST = true
```

---

## Etapa 5 — Exibir Decisão e Executar

Exiba a decisão tomada:

```
## Orchestrator — Roteamento

**Task:** <TASK-ID> — <summary>
**Tipo detectado:** <TIPO>
**Sinais:** labels=<labels>, priority=<priority>, repo_type=<REPO_TYPE>
**Workflow:** <SKILL> <FLAGS>
**Runbook:** <RUNBOOK_PATH ou "nenhum">
**Falhas recentes:** <sim/não>
```

### 5.1 — Init se necessário

Se `INIT_FIRST = true`:

```
Repo sem CLAUDE.md detectado. Executando /init primeiro...
```

Invoque `/init` e aguarde conclusão.

### 5.2 — Carregar runbook

Se `$RUNBOOK_PATH` não está vazio, leia o runbook e inclua as instruções no contexto:

```bash
cat "$RUNBOOK_PATH"
```

As instruções do runbook devem ser seguidas pelo engineer durante a implementação.

### 5.3 — Invocar skill

Invoque a skill escolhida passando `--task $TASK_ID` para que o engineer **pule a busca no Jira** (a task já foi selecionada aqui):

```
/<SKILL> --task <TASK-ID> <FLAGS>
```

Exemplos:
- `/engineer --task AZUL-1234 --skip-clarity --fast-ci --min-reviewers 1`
- `/engineer-multi --task AZUL-5678`
- `/engineer --task AZUL-9999 --runbook docs/runbooks/large-refactoring.md`
- `/engineer --task AZUL-0000` (feature normal, sem flags extras)

**CRITICAL:** Sempre passe `--task`. Sem essa flag o engineer buscaria outra task do Jira, duplicando trabalho.

### 5.4 — Registrar decisão

Registre a decisão para análise futura:

```bash
source ~/.ai-engineer/scripts/execution-log.sh 2>/dev/null
exec_log "orchestrator" "$TASK_ID" "routed" \
  "{\"tipo\": \"$TIPO\", \"skill\": \"$SKILL\", \"flags\": \"$FLAGS\", \"runbook\": \"$RUNBOOK_PATH\"}" \
  2>/dev/null || true
```

---

## Regras

- **Fallback é sempre feature** — se nenhuma regra bater, siga o fluxo padrão do engineer.
- **Não bloqueie** — se o Jira estiver inacessível, assuma tipo "feature" e prossiga.
- **Labels têm precedência** — labels explícitas (hotfix, refactoring) são mais confiáveis que análise de texto.
- **Registre toda decisão** — o log permite auditar e ajustar as regras ao longo do tempo.
- **O engineer continua funcionando sozinho** — o orchestrator é uma camada adicional, não substitui o engineer.
