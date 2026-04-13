# AI Engineer

[![CI](https://github.com/wallacehenriquesilva/ai-engineer/actions/workflows/ci.yml/badge.svg)](https://github.com/wallacehenriquesilva/ai-engineer/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-2.0.0-blue)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Agente autonomo de desenvolvimento para times de engenharia. Busca tasks do Jira, implementa codigo, roda testes, abre PRs, resolve comentarios de revisao e faz deploy — tudo sem intervencao humana.

Construido sobre [Claude Code](https://claude.ai/code) com arquitetura de **pipeline de agentes**: cada etapa roda em um sub-agent isolado com contexto descartavel, coordenado por um orchestrator central.

---

## Arquitetura

O AI Engineer usa 3 primitivos:

| Primitivo | O que e | Exemplo |
|---|---|---|
| **Command** | Entrada do usuario, leve (~10 linhas) | `/engineer`, `/run`, `/run-queue` |
| **Agent** | Worker autonomo em contexto isolado | orchestrator, engineer, evaluator |
| **Skill** | Conhecimento carregado pelos agents | security, testing-patterns, rest-api |

**Principio:** Agents sao atores. Skills sao conhecimento. Scripts sao encanamento.

---

## Fluxo Completo: `/engineer`

O comando `/engineer` dispara o pipeline completo para implementar uma task:

```
Usuario: /engineer
  |
  |  Command (leve, so spawna o orchestrator)
  |
  └── @orchestrator (Sonnet) ─── cerebro do pipeline
        |
        |  PASSO 1 — Buscar Task
        ├── @task-fetcher (Sonnet)
        |     ├── Busca sprint ativa no Jira (board do CLAUDE.md)
        |     ├── JQL: status "To Do", label AI, sem flag, sem bloqueio
        |     ├── Valida: issuelinks (bloqueios), flagged (impedimentos)
        |     └── Retorna: TaskContext JSON
        |           {task_id, summary, labels, priority, description,
        |            acceptance_criteria, repo_name, repo_type}
        |
        |  PASSO 2 — Classificar Task (hibrido: script + LLM)
        ├── task-classifier.sh (deterministico, zero tokens)
        |     ├── label "hotfix" ou priority P0/P1 → tipo: hotfix
        |     ├── label "refactoring"/"tech-debt" → tipo: refactoring
        |     ├── repo tipo terraform → tipo: infra
        |     ├── label "integration"/"new-consumer" → tipo: integration
        |     └── nenhuma regra bateu → tipo: unknown
        |
        ├── Se unknown: orchestrator interpreta descricao (LLM)
        |     ├── "bug critico em producao" → hotfix
        |     ├── menciona 2+ repos → multi-repo
        |     ├── "migrar", "renomear" → refactoring
        |     └── default → feature
        |
        ├── runbook-matcher.sh → seleciona runbook por frontmatter
        |
        |  PASSO 3 — Implementar
        ├── @engineer (Opus) ─── o unico que precisa raciocinar sobre codigo
        |     ├── Avalia clareza da task (pula se --skip-clarity)
        |     |     Se insuficiente → comenta no Jira, encerra
        |     ├── Consulta aprendizados (knowledge-client.sh)
        |     ├── Le codebase: estrutura, padroes, frameworks
        |     ├── Carrega skills condicionais:
        |     |     repo Go → ca-golang-developer
        |     |     repo Terraform → ca-infra-developer
        |     |     task com API → rest-api
        |     |     task com DB → sql + database-migration
        |     ├── Planeja implementacao
        |     ├── Implementa codigo de producao
        |     └── Retorna: {files_changed, plan_summary}
        |
        |     Se tipo = multi-repo:
        |     └── @engineer-multi (Opus) em vez de @engineer
        |           ├── Classifica repos: Infra → Producer → Consumer
        |           ├── Implementa em ordem de dependencia
        |           └── Exporta contratos entre repos
        |
        |  PASSO 4 — Testar
        ├── @tester (Sonnet)
        |     ├── Carrega skill: testing-patterns
        |     ├── Le arquivos alterados
        |     ├── Escreve testes (table-driven, mocks, edge cases)
        |     ├── Roda testes: go test / npm test / mvn test
        |     └── Retorna: {tests_passed, coverage}
        |
        |     Se falhou → re-spawna @engineer com erro (max 1 retry)
        |
        |  PASSO 5 — Avaliar (contexto isolado, sem vies)
        ├── @evaluator (Sonnet)
        |     ├── Carrega skills: security, code-review, testing-patterns
        |     ├── Postura cetica: default e NEEDS WORK
        |     ├── Avalia: corretude, seguranca, testes, qualidade
        |     ├── Classifica: blocker (FAIL) vs suggestion (PASS)
        |     └── Retorna: {verdict: PASS|FAIL, blockers, suggestions}
        |
        |     Se FAIL → re-spawna @engineer com blockers (max 2 ciclos)
        |
        |  PASSO 6 — Atualizar Docs
        ├── @docs-updater (Sonnet)
        |     ├── Compara arquivos alterados com docs existentes
        |     ├── Detecta: novo consumer, env var, endpoint, migration
        |     ├── Atualiza CLAUDE.md/README do repo (se existem)
        |     └── Retorna: {docs_updated} ou skip
        |
        |  PASSO 7 — Abrir PR
        ├── @pr-manager (Sonnet)
        |     ├── DORA commit vazio (metricas)
        |     ├── Cria worktree + branch: <TASK-ID>/<descricao>
        |     ├── Commits semanticos (feat:/fix:/test:) com Co-Authored-By
        |     ├── Abre PR com template padrao
        |     ├── Solicita review do time (GitHub Team)
        |     ├── Aciona CI (auto ou comment trigger)
        |     ├── Aguarda todos os checks ficarem green
        |     └── Retorna: {pr_url, branch, ci_status}
        |
        └── Resultado final ao command:
              {task_id, pr_url, branch, ci_status, status: "success"}
```

---

## Fluxo: `/run` (ciclo completo)

Encadeia implementacao + resolucao de reviews + deploy:

```
Usuario: /run
  |
  ├── FASE 1: @orchestrator (pipeline acima)
  |     └── Retorna: {task_id, pr_url, worktree}
  |
  ├── FASE 2: @pr-resolver (Opus)
  |     ├── Monitora PR aguardando feedback (polling 24h)
  |     ├── Classifica comentarios: bug, sugestao, pergunta, nitpick
  |     ├── Implementa correcoes (fix: commits)
  |     ├── Responde revisores com contexto tecnico
  |     ├── Trata bots (SonarQube, Aikido) como bloqueantes
  |     ├── Push + aguarda CI apos cada correcao
  |     └── Retorna: {status: approved, comments_resolved, fix_commits}
  |
  └── FASE 3: @finalizer (Sonnet)
        ├── Valida aprovacao da PR
        ├── Deploy sandbox → aguarda checks
        ├── Deploy homolog → aguarda checks
        ├── Merge (squash + delete branch)
        ├── Monitora deploy em producao
        ├── Atualiza Jira → Done
        └── Retorna: {deployed: true, jira_status: Done}
```

---

## Fluxo: `/run-queue` (execucao continua)

Processa multiplas tasks sem bloquear esperando review:

```
Usuario: /run-queue --max-tasks 10 --max-active 5
  |
  └── Loop continuo:
        |
        ├── 1. wq_poll_prs
        |     Verifica status de todas as PRs via GitHub API:
        |     - PR merged/closed → done
        |     - Review approved → approved
        |     - Changes requested → has_feedback
        |     - Novos comentarios → has_feedback
        |     - CI falhando → has_feedback
        |
        ├── 2. wq_next_action (prioridade fixa)
        |     has_feedback  → resolve (PRIORIDADE 1)
        |     approved      → finalize (PRIORIDADE 2)
        |     nenhum acima  → implement (PRIORIDADE 3)
        |
        ├── 3a. Se RESOLVE:
        |     └── @pr-resolver --no-poll
        |           Resolve comentarios existentes e retorna
        |           (sem entrar em polling de 24h)
        |
        ├── 3b. Se FINALIZE:
        |     └── @finalizer
        |           Deploy + merge + Jira
        |
        ├── 3c. Se IMPLEMENT:
        |     ├── Verifica limite de PRs ativas
        |     └── @orchestrator
        |           Pipeline completo → PR aberta → adiciona ao queue
        |
        ├── 4. Atualiza queue (SQLite)
        |     wq_add / wq_set_pr / wq_update_pr / wq_done_pr
        |
        └── 5. Repete ate max_tasks ou circuit breaker

  Estado persiste em ~/.ai-engineer/queue.db
  Sessoes podem ser retomadas: /run-queue
```

---

## Fluxo: `/run-parallel` (workers paralelos)

```
Usuario: /run-parallel --workers 3
  |
  ├── Busca 3 tasks via @task-fetcher (uma por worker)
  |
  ├── Spawna 3 @orchestrator em paralelo (worktrees isolados)
  |     Worker 1: AZUL-1234 → implementa em worktree isolado
  |     Worker 2: AZUL-5678 → implementa em worktree isolado
  |     Worker 3: AZUL-9999 → implementa em worktree isolado
  |
  └── Coleta resultados:
        Worker 1: AZUL-1234 | PR #123 | success
        Worker 2: AZUL-5678 | PR #456 | success
        Worker 3: no_task
```

---

## Agents

| Agent | Modelo | Responsabilidade |
|---|---|---|
| `orchestrator` | Sonnet | Cerebro do pipeline — coordena todos os sub-agents |
| `task-fetcher` | Sonnet | Busca task no Jira, valida bloqueios e flags |
| `engineer` | **Opus** | Planeja e implementa codigo (core) |
| `tester` | Sonnet | Escreve e roda testes |
| `evaluator` | Sonnet | Revisao independente com postura cetica |
| `pr-manager` | Sonnet | Git ops: branch, commits, PR, CI |
| `docs-updater` | Sonnet | Atualiza docs existentes com base no que mudou |
| `pr-resolver` | **Opus** | Resolve comentarios de review, responde revisores |
| `finalizer` | Sonnet | Deploy sandbox → homolog → producao |
| `engineer-multi` | **Opus** | Coordena implementacao em 2+ repos |

Apenas `engineer`, `pr-resolver` e `engineer-multi` usam Opus (raciocinio sobre codigo). Os demais usam Sonnet (mecanicos). Economia estimada de ~40-50% vs tudo em Opus.

---

## Skills (conhecimento)

Skills sao carregadas **condicionalmente** pelos agents:

| Skill | Carregada por | Quando |
|---|---|---|
| `ca-golang-developer` | engineer | Repo Go |
| `ca-infra-developer` | engineer | Repo Terraform |
| `testing-patterns` | engineer, tester, evaluator | Sempre |
| `security` | evaluator | Sempre |
| `code-review` | evaluator, pr-resolver | Sempre |
| `rest-api` | engineer | Task envolve API |
| `sql` | engineer | Task envolve DB |
| `database-migration` | engineer | Task com migration |
| `docker` | engineer | Task com Docker |
| `observability` | engineer | Task com metricas/logs |
| `performance` | engineer | Task de otimizacao |

---

## Instalacao

```bash
git clone https://github.com/wallacehenriquesilva/ai-engineer.git
cd ai-engineer
./install.sh
```

O instalador copia commands, agents e skills para `~/.claude/` e scripts para `~/.ai-engineer/`:

```
[1/7] Verificando dependencias        (jq, git, gh, Claude Code)
[2/7] Verificando autenticacoes       (GitHub CLI)
[3/7] Configurando integracoes        (GitHub MCP, Jira MCP, Slack MCP)
[4/7] Instalando commands, agents e skills
[5/7] Configurando knowledge-service  (Gemini API key para embeddings)
[6/7] Iniciando knowledge-service     (Docker: PostgreSQL + pgvector)
[7/7] Finalizando
```

### Pre-requisitos

| Dependencia | Obrigatorio | Para que |
|---|---|---|
| [Claude Code](https://claude.ai/code) | Sim | Runtime do agente |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Sim | PRs, CI, MCP do GitHub |
| [jq](https://jqlang.github.io/jq/) | Sim | Parsing de JSON nos scripts |
| [Git](https://git-scm.com/) | Sim | Worktrees, commits, PRs |
| [uv](https://docs.astral.sh/uv/) (uvx) | Recomendado | MCP do Atlassian |
| [Docker](https://docker.com) | Opcional | Knowledge-service (busca semantica) |

> **Sem Docker?** O agente funciona normalmente com SQLite local. Apenas busca semantica fica indisponivel.

### Atualizar

```bash
./install.sh --update    # atualiza commands, agents, skills e scripts
./install.sh --skills    # reinstala tudo (commands + agents + skills)
```

---

## Inicio rapido

```bash
# 1. Instale (uma vez)
./install.sh

# 2. Va para a raiz dos seus repos
cd ~/git
claude

# 3. Teste sem risco (configura o time na primeira vez)
/engineer --dry-run

# 4. Execute de verdade
/engineer

# 5. Ciclo completo (implementa + resolve reviews + deploy)
/run

# 6. Modo continuo (processa multiplas tasks)
/run-queue --max-tasks 10
```

---

## Comandos

| Comando | O que faz |
|---|---|
| `/engineer` | Implementa a proxima task do Jira |
| `/engineer --dry-run` | Simula sem criar branch, PR ou mover task |
| `/run` | Ciclo completo: implementa + resolve reviews + deploy |
| `/run-queue` | Execucao continua com work queue |
| `/run-parallel --workers 3` | Tasks em paralelo com worktrees isolados |
| `/pr-resolve <url>` | Resolve comentarios de revisao |
| `/finalize <url>` | Deploy: sandbox → homolog → producao |
| `/init` | Gera CLAUDE.md analisando o repositorio |
| `/history --stats` | Estatisticas dos ultimos 30 dias |

---

## Guardrails

| Guardrail | Padrao | O que faz |
|---|---|---|
| Dry-run | `--dry-run` | Simula sem acoes destrutivas |
| Budget limit | $5.00 | Interrompe se custo ultrapassar |
| Confidence threshold | 15/18 | Nao implementa se clareza insuficiente |
| Circuit breaker | 3 falhas | Para apos N falhas consecutivas |
| CI max retries | 2 | Maximo de tentativas de CI |
| Evaluator | Postura cetica | NEEDS WORK por padrao, max 2 ciclos |
| Bloqueios Jira | Ativo | Nunca pega task bloqueada |
| Flags Jira | Ativo | Nunca pega task com marcador/impedimento |
| Backlog | Proibido | Nunca busca fora da sprint ativa |
| Merge | Aprovacao humana | So com review aprovada |
| Rollback | Automatico | Revert se producao falhar |

---

## Classificacao de Tasks

O orchestrator classifica tasks usando abordagem hibrida:

**Camada 1 — Script (deterministico, zero tokens):**

| Sinal | Tipo | Flags |
|---|---|---|
| Label `hotfix`/`incident` ou priority P0/P1 | hotfix | `--skip-clarity --fast-ci` |
| Label `refactoring`/`tech-debt` | refactoring | `--runbook large-refactoring.md` |
| Repo tipo Terraform | infra | `--skip-app-tests` |
| Label `integration`/`new-consumer` | integration | `--runbook new-integration.md` |

**Camada 2 — LLM (fallback para casos ambiguos):**

Quando nenhuma regra explicita bate, o orchestrator interpreta a descricao da task.

---

## Aprendizado e Auto-Promocao

O agente aprende com erros e compartilha entre execucoes:

```
1. Agente erra → registra aprendizado (pattern + solution)
2. Mesmo erro acontece de novo → incrementa times_seen
3. times_seen >= threshold → candidato a promocao
4. Agente gera regra → abre PR no CLAUDE.md do repo
5. Time aprova → regra vira contexto permanente
6. Agente nunca mais erra dessa forma
```

Storage: knowledge-service (PostgreSQL + pgvector) ou SQLite local (fallback automatico).

---

## Notificacoes no Slack

Configuravel no CLAUDE.md:

```markdown
Slack Auto Review: true
Slack Review Channel: C0APYR0N7B4
```

1. PR pronta → envia mensagem no canal mencionando o grupo de revisao
2. Comentarios resolvidos → responde na thread
3. PR merged → atualiza thread

---

## Estrutura do repositorio

```
ai-engineer/
├── commands/                        # Entrada do usuario (leves, ~10 linhas)
│   ├── engineer.md                  # /engineer
│   ├── run.md                       # /run
│   ├── run-queue.md                 # /run-queue
│   ├── run-parallel.md              # /run-parallel
│   ├── pr-resolve.md                # /pr-resolve <url>
│   ├── finalize.md                  # /finalize <url>
│   ├── init.md                      # /init
│   └── history.md                   # /history
├── agents/                          # Workers autonomos (contexto isolado)
│   ├── orchestrator.md              # cerebro do pipeline (Sonnet)
│   ├── task-fetcher.md              # busca task no Jira (Sonnet)
│   ├── engineer.md                  # planeja e implementa (Opus)
│   ├── tester.md                    # escreve e roda testes (Sonnet)
│   ├── evaluator.md                 # revisao independente (Sonnet)
│   ├── pr-manager.md                # git ops, PR, CI (Sonnet)
│   ├── docs-updater.md              # atualiza docs (Sonnet)
│   ├── pr-resolver.md               # resolve reviews (Opus)
│   ├── finalizer.md                 # deploy (Sonnet)
│   └── engineer-multi.md            # multi-repo (Opus)
├── skills/                          # Conhecimento (carregado pelos agents)
│   ├── security/                    # OWASP Top 10, secrets, injection
│   ├── testing-patterns/            # unit/integration, mocks, edge cases
│   ├── code-review/                 # code smells, SOLID, complexidade
│   ├── rest-api/                    # design de APIs RESTful
│   ├── sql/                         # queries seguras, indexes
│   ├── database-migration/          # zero-downtime, expand-contract
│   ├── docker/                      # multi-stage, seguranca
│   ├── observability/               # logs, metricas, traces
│   ├── performance/                 # gargalos, caching
│   ├── jira-integration/            # operacoes no Jira
│   ├── jira-task-clarity/           # avaliacao de clareza
│   ├── git-workflow/                # worktree, commits, PR
│   ├── execution-feedback/          # aprendizado compartilhado
│   ├── knowledge-query/             # busca no knowledge base
│   └── slack-review/                # notificacoes no Slack
├── scripts/                         # Deterministico (sem LLM)
│   ├── task-classifier.sh           # classificacao por regras
│   ├── runbook-matcher.sh           # match de runbook por frontmatter
│   ├── work-queue.sh                # fila SQLite
│   ├── knowledge-client.sh          # client unificado (HTTP + SQLite)
│   ├── knowledge-local.sh           # fallback SQLite
│   ├── execution-log.sh             # log + handoff state
│   └── calculate-cost.sh            # calculo de custo
├── knowledge-service/               # API Go (pgvector + embeddings)
├── docs/
│   ├── ARCHITECTURE.md              # principios: scripts, agents, skills
│   ├── MIGRATION-V2.md              # plano de migracao detalhado
│   └── runbooks/                    # guias para cenarios especiais
│       ├── hotfix-p0.md
│       ├── large-refactoring.md
│       └── new-integration.md
├── .claude-plugin/plugin.json       # manifesto do plugin
├── install.sh                       # instalador (commands + agents + skills + scripts)
└── CLAUDE.md                        # configuracao do time
```

---

## Testes

```bash
make test-all        # roda tudo (Go + skills + execution-log)
make test-skills     # checks de estrutura
make test-exec-log   # checks do execution-log
make test            # testes Go do knowledge-service
```

---

## Contribuindo

PRs sao bem-vindas! Veja [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes.

## Licenca

MIT — veja [LICENSE](LICENSE) para detalhes.
