# AI Engineer

[![CI](https://github.com/wallacehenriquesilva/ai-engineer/actions/workflows/ci.yml/badge.svg)](https://github.com/wallacehenriquesilva/ai-engineer/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.1.0-blue)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-204%20checks-brightgreen)](#testes)

Desenvolvedor autonomo para times de engenharia. Pega tasks do Jira, implementa codigo, roda testes, abre PRs, resolve comentarios de revisao, notifica o time no Slack e faz deploy — tudo sem intervencao humana.

Construido sobre [Claude Code](https://claude.ai/code).

---

## Por que usar

| Problema | Como o AI Engineer resolve |
|---|---|
| Tasks acumulam na sprint sem ninguem pegar | Busca automaticamente a proxima task com label `AI` |
| Implementacoes fora do padrao do time | Aprende os padroes do repo via `CLAUDE.md` e skills |
| PRs rejeitadas por falta de testes | Roda testes e corrige falhas antes de abrir a PR |
| PR aberta mas ninguem revisa | Notifica o time no Slack com menção do grupo correto |
| Agente faz deploy sem confirmacao | Gate de seguranca exige aprovacao humana antes do merge |
| Fica bloqueado esperando review | Work queue permite pegar a proxima task enquanto espera |
| Mesmo erro acontece em varias execucoes | Registra aprendizados e consulta antes de implementar |
| Cada maquina aprende isolada | Knowledge-service centralizado compartilha entre agentes |
| Vulnerabilidades passam despercebidas | Auto-review de seguranca antes de abrir PR |

---

## Como funciona

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Jira      │     │  Implementar │     │   Testar     │     │   Entregar   │
│             │     │              │     │              │     │              │
│ Busca task  ├────>│ Analisa repo ├────>│ Roda testes  ├────>│ Abre PR      │
│ Avalia      │     │ Planeja      │     │ Auto-review  │     │ Aguarda CI   │
│ clareza     │     │ Implementa   │     │ Seguranca    │     │ Notifica     │
└─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                    │                    │                    │
       │ Clareza < 15/18?   │ Budget > limite?   │ Vulnerabilidade?   │ CI falhou?
       │ Comenta no Jira    │ Interrompe         │ Corrige            │ Corrige
       ▼                    ▼                    ▼                    ▼
    [ENCERRA]           [ENCERRA]          [CORRIGE 2x]        [CORRIGE 2x]
```

---

## Instalacao

Um comando instala tudo: dependencias, MCPs, autenticacoes e knowledge-service.

```bash
git clone https://github.com/wallacehenriquesilva/ai-engineer.git
cd ai-engineer
./install.sh
```

O instalador guia por 7 etapas:

```
[1/7] Verificando dependencias        (jq, git, gh, Claude Code)
[2/7] Verificando autenticacoes       (GitHub CLI)
[3/7] Configurando integracoes        (GitHub MCP, Jira MCP, Slack MCP)
[4/7] Instalando skills               (copia para ~/.claude/skills/)
[5/7] Configurando knowledge-service  (Gemini API key para embeddings)
[6/7] Iniciando knowledge-service     (Docker: PostgreSQL + pgvector)
[7/7] Finalizando                     (salva versao)
```

### Pre-requisitos

| Dependencia | Obrigatorio | Para que |
|---|---|---|
| [Git](https://git-scm.com/) | Sim | Worktrees, clone, commits, PRs |
| [Claude Code](https://claude.ai/code) | Sim | Runtime do agente |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Sim | PRs, CI, MCP do GitHub |
| [jq](https://jqlang.github.io/jq/) | Sim | Parsing de JSON nos scripts |
| [uv](https://docs.astral.sh/uv/) (uvx) | Recomendado | MCP do Atlassian (alternativa: npx ou Docker) |
| [Node.js](https://nodejs.org/) (npx) | Opcional | MCP do Slack |
| [Docker](https://docker.com) | Opcional | Knowledge-service (busca semantica e aprendizados) |

### Atualizar

```bash
./install.sh --update    # atualiza skills, scripts e knowledge-service
./install.sh --skills    # reinstala apenas as skills
```

---

## Inicio rapido

```bash
# 1. Instale (uma vez)
./install.sh

# 2. Verifique que esta tudo OK
make check

# 3. Va para a raiz dos seus repos e abra o Claude Code
cd ~/git
claude

# 4. Teste sem risco (na primeira vez, configura o time automaticamente)
/engineer --dry-run

# 5. Execute de verdade
/engineer
```

> **Sem Docker?** O agente funciona normalmente. Apenas busca semantica e aprendizados compartilhados ficam indisponiveis.

---

## Comandos

| Comando | O que faz |
|---|---|
| `/engineer` | Implementa a proxima task do Jira (ciclo completo) |
| `/engineer --dry-run` | Simula tudo sem criar branch, PR ou mover task |
| `/run` | Ciclo completo: engineer + resolve comentarios + deploy |
| `/run-queue` | Execucao continua com work queue — nao bloqueia esperando review |
| `/run-parallel --workers 3` | Executa multiplas tasks em paralelo |
| `/pr-resolve <url>` | Monitora PR, classifica e resolve comentarios de revisao |
| `/finalize <url>` | Deploy: sandbox, homolog, producao + merge |
| `/history --stats` | Estatisticas dos ultimos 30 dias |
| `/init` | Gera CLAUDE.md analisando o repositorio |

---

## Execucao continua (Work Queue)

O modo recomendado para processar multiplas tasks:

```
/run-queue --max-tasks 10 --max-active 5
```

Em vez de bloquear esperando review de cada PR, o agente:

1. Pega uma task, implementa, abre PR
2. Pega a proxima task enquanto aguarda review
3. Monitora todas as PRs em background (SQLite)
4. Quando uma PR recebe feedback → resolve imediatamente (prioridade)
5. Quando uma PR e aprovada → finaliza e faz deploy (prioridade)

```
Prioridade: resolver feedback > finalizar aprovadas > implementar nova task
```

O estado persiste em `~/.ai-engineer/queue.db` — sessoes podem ser retomadas.

| Flag | Padrao | O que faz |
|---|---|---|
| `--max-tasks` | 10 | Maximo de tasks a processar |
| `--max-active` | 5 | Maximo de PRs ativas simultaneamente |
| `--poll-interval` | 60 | Intervalo de polling em segundos |

---

## Notificacoes no Slack

O agente notifica o time automaticamente quando uma PR esta pronta para review:

1. **Abre PR + CI verde** → envia mensagem no canal do Slack mencionando o grupo de revisao
2. **Resolve comentarios** → responde na thread notificando os revisores
3. **PR merged** → atualiza a thread com indicador de merge

Configuravel no `CLAUDE.md`:

```markdown
## Slack (opcional)

Slack Auto Review: true
Slack Review Channel: C0APYR0N7B4

## Slack User Map
- user.github: U0ABC123

## Slack Review Groups
- backend: @team-backends
- frontend: @team-frontend
- default: @team-all
```

Requer MCP do Slack (`npx @modelcontextprotocol/server-slack`), configurado automaticamente pelo instalador.

---

## Guardrails

| Guardrail | Padrao | O que faz |
|---|---|---|
| **Dry-run** | `--dry-run` | Simula sem executar acoes destrutivas |
| **Budget limit** | $5.00 | Interrompe se o custo ultrapassar o limite |
| **Confidence threshold** | 15/18 | Nao implementa se a clareza da task for insuficiente |
| **Circuit breaker** | 3 falhas | Para de pegar tasks apos N falhas consecutivas |
| **CI max retries** | 2 | Maximo de tentativas de correcao de CI |
| **Auto-review** | Ativo | Valida acceptance criteria e seguranca antes de abrir PR |
| **Bloqueios Jira** | Ativo | Nunca pega task com bloqueio nao resolvido |
| **Merge automatico** | PR aprovada + homolog | Merge so acontece com aprovacao humana |
| **Rollback** | Automatico | Executa revert se o deploy em producao falhar |

Todos configuraveis no `CLAUDE.md` do time.

---

## Seguranca

O agente valida seguranca antes de abrir PR (Etapa 9.2 do engineer):

1. **Detecta a linguagem** do repo (Go, JS, Java, Python, Terraform)
2. **Busca skill de seguranca** instalada (`security-go`, `security-js`, ou generica `security`)
3. **Se encontrou** → invoca a skill para analise completa
4. **Se nao encontrou** → checagem basica: secrets hardcoded, SQL injection, XSS, command injection, credenciais em codigo

Comentarios de bots de seguranca (Aikido, Snyk, etc.) nas PRs sao tratados como **bloqueantes** — o agente corrige antes de prosseguir.

---

## Multi-repo

Quando uma task envolve multiplos repositorios (ex: app + infra):

1. Classifica repos: Producer (API) e Consumer (frontend/infra)
2. Implementa o Producer primeiro
3. Exporta o contrato (endpoints, payloads)
4. Implementa o Consumer usando o contrato
5. Abre PRs referenciando uma a outra
6. Work queue monitora ambas as PRs — task so e concluida quando todas estao done

---

## Evidencias

O finalize gera evidencias padronizadas para cada ambiente:

**Backend:** request/response com status HTTP para sandbox, homolog e producao.

**Frontend:** screenshots via Playwright em cada ambiente, com validacao visual.

Templates em `skills/finalize/templates/`:
- `evidence-backend.md`
- `evidence-frontend.md`

---

## Aprendizado compartilhado

Agentes em diferentes maquinas compartilham aprendizados via knowledge-service:

```
Agente A falha: "mock desatualizado ao adicionar campo no model"
                          |
                          v
              +------------------------+
              |  Knowledge Service     |
              |  (PostgreSQL+pgvector) |
              |  pattern registrado    |
              +------------------------+
                          |
Agente B consulta antes de implementar:
  "Aprendizado: verificar mocks ao alterar models (visto 3x)"
```

Quando um pattern atinge `times_seen >= 3`, e listado para promocao ao `CLAUDE.md` do repo.

---

## Flags

| Flag | Comando | O que faz |
|---|---|---|
| `--dry-run` | `/engineer` | Simula sem criar branch, PR ou mover task |
| `--budget 10.00` | `/engineer` | Define limite de custo para a sessao |
| `--force` | `/engineer` | Ignora circuit breaker |
| `--max-tasks 10` | `/run-queue` | Maximo de tasks a processar |
| `--max-active 5` | `/run-queue` | Maximo de PRs ativas simultaneamente |
| `--workers 3` | `/run-parallel` | Numero de tasks em paralelo |
| `--no-poll` | `/pr-resolve` | Resolve comentarios sem polling (usado pelo run-queue) |
| `--stats` | `/history` | Mostra estatisticas agregadas |
| `--status failure` | `/history` | Filtra por status |
| `--limit 10` | `/history` | Limita numero de resultados |
| `--days 30` | `/history` | Periodo de analise |

---

## Estrutura do repositorio

```
ai-engineer/
├── skills/                          # Skills (o que o agente sabe fazer)
│   ├── engineer/                    # implementacao de task
│   ├── engineer-multi/              # tasks com 2+ repos
│   ├── pr-resolve/                  # resolucao de comentarios de PR
│   ├── finalize/                    # deploy e merge
│   │   └── templates/               # templates de evidencias
│   ├── run/                         # ciclo completo sequencial
│   │   └── templates/               # templates de handoff
│   ├── run-queue/                   # execucao continua com work queue
│   ├── run-parallel/                # execucao paralela
│   ├── history/                     # historico e estatisticas
│   ├── init/                        # gera CLAUDE.md do repo
│   ├── jira-integration/            # operacoes no Jira
│   ├── jira-task-clarity/           # avaliacao de clareza de tasks
│   ├── git-workflow/                # worktree, commits, PR, CI
│   │   ├── templates/               # template de PR
│   │   └── examples/                # exemplos de commit e PR
│   ├── execution-feedback/          # aprendizado entre execucoes
│   ├── knowledge-query/             # busca semantica
│   └── slack-review/                # notificacoes de review no Slack
│       └── references/              # templates de mensagem
├── scripts/
│   ├── work-queue.sh                # work queue SQLite
│   ├── execution-log.sh             # log de execucoes + handoff state
│   ├── knowledge-client.sh          # client para o knowledge-service
│   ├── calculate-cost.sh            # calculo de custo da sessao
│   ├── lint-skills.sh               # validacao de skills
│   ├── run-parallel.sh              # worker pool
│   ├── run-loop.sh                  # loop continuo externo
│   ├── org-scan.sh                  # carga inicial do knowledge base
│   └── org-watch.sh                 # atualizacao delta
├── knowledge-service/               # API Go (pgvector + Gemini embeddings)
├── docs/
│   ├── PROJECT.md                   # documentacao completa com flowcharts
│   ├── CLAUDE.md.template           # template de configuracao do time
│   ├── COMPARISON-AGENCY-AGENTS.md  # analise comparativa
│   └── runbooks/                    # guias para cenarios especiais
│       ├── hotfix-p0.md
│       ├── large-refactoring.md
│       └── new-integration.md
├── tests/
│   ├── test-skills.sh               # 204 checks de estrutura
│   ├── test-execution-log.sh        # 28 checks do execution-log
│   └── main_test.go                 # testes Go (knowledge-service)
├── .claude-plugin/plugin.json       # manifesto do plugin
├── install.sh                       # instalador interativo
├── Makefile                         # atalhos (setup, test, install, etc.)
└── CLAUDE.md                        # configuracao do time
```

---

## Testes

```bash
make test-all        # roda tudo (Go + skills + execution-log)
make test-skills     # 204 checks de estrutura
make test-exec-log   # 28 checks do execution-log
make test            # testes Go do knowledge-service
```

---

## Criando uma nova skill

```
skills/<nome-da-skill>/
├── SKILL.md              # obrigatorio
├── templates/            # opcional
├── examples/             # opcional
└── references/           # opcional
```

Frontmatter do `SKILL.md`:

```markdown
---
name: minha-skill
version: 1.0.0
description: >
  Quando o agente deve acionar esta skill.
depends-on:
  - git-workflow
triggers:
  - user-command: /minha-skill
  - called-by: engineer
allowed-tools:
  - Bash
  - Read
  - Edit
---
```

| Campo | Obrigatorio | Descricao |
|---|---|---|
| `name` | Sim | Identificador unico |
| `version` | Recomendado | Versao semantica |
| `description` | Sim | Quando acionar — o agente le isso para decidir |
| `depends-on` | Recomendado | Skills que esta skill invoca |
| `triggers` | Recomendado | Eventos que ativam esta skill |
| `allowed-tools` | Sim | Ferramentas que a skill pode usar |

Validar e instalar:

```bash
./scripts/lint-skills.sh          # valida estrutura
./install.sh --skills             # instala no Claude Code
```

---

## Contribuindo

PRs sao bem-vindas! Veja [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes.

## Licenca

MIT — veja [LICENSE](LICENSE) para detalhes.
