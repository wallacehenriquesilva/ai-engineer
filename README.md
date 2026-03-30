# AI Engineer

[![CI](https://github.com/wallacehenriquesilva/ai-engineer/actions/workflows/ci.yml/badge.svg)](https://github.com/wallacehenriquesilva/ai-engineer/actions/workflows/ci.yml)
[![Versão](https://img.shields.io/badge/versão-0.1.0-blue)](CHANGELOG.md)
[![Licença](https://img.shields.io/badge/licença-MIT-green)](LICENSE)
[![Testes](https://img.shields.io/badge/testes-162%20checks-brightgreen)](#testes)

Desenvolvedor autônomo para times de engenharia. Pega tasks do Jira, implementa código, roda testes, abre PRs e resolve comentários de revisão — tudo sem intervenção humana.

Construído sobre [Claude Code](https://claude.ai/code).

<!-- Demo: grave um GIF de ~30s do /engineer --dry-run e salve em docs/demo.gif -->
<!-- Sugestão: use https://github.com/charmbracelet/vhs ou asciinema para gravar -->
<p align="center">
  <img src="docs/demo.gif" alt="AI Engineer em ação" width="800">
</p>

---

## Por que usar

| Problema | Como o AI Engineer resolve |
|---|---|
| Tasks acumulam na sprint sem ninguém pegar | Busca automaticamente a próxima task com label `AI` |
| Implementações fora do padrão do time | Aprende os padrões do repo via `CLAUDE.md` e skills |
| PRs rejeitadas por falta de testes | Roda testes e corrige falhas antes de abrir a PR |
| Agente faz deploy sem confirmação | Gate de segurança exige aprovação humana antes do merge |
| Mesmo erro acontece em várias execuções | Registra aprendizados e consulta antes de implementar |
| Cada máquina aprende isolada | Knowledge-service centralizado compartilha entre agentes |

---

## Como funciona

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Jira      │     │  Implementar │     │   Testar     │     │   Entregar   │
│             │     │              │     │              │     │              │
│ Busca task  ├────►│ Analisa repo ├────►│ Roda testes  ├────►│ Abre PR      │
│ Avalia      │     │ Planeja      │     │ Corrige      │     │ Aciona CI    │
│ clareza     │     │ Implementa   │     │ falhas       │     │ Move task    │
└─────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                    │                                        │
       │ Clareza < 15/18?   │ Budget > limite?                       │ CI falhou?
       │ Comenta no Jira    │ Interrompe e preserva                  │ Corrige (2x max)
       ▼                    ▼                                        ▼
    [ENCERRA]           [ENCERRA]                              [ENCERRA se 2x]
```

---

## Instalação

Um comando instala tudo: dependências, MCPs, autenticações e knowledge-service.

**Mac / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/wallacehenriquesilva/ai-engineer/main/install.ps1 | iex
```

**Ou clone e execute:**
```bash
git clone https://github.com/wallacehenriquesilva/ai-engineer.git
cd ai-engineer
./install.sh        # Mac/Linux
.\install.ps1       # Windows
```

O instalador guia você por 7 etapas:

```
[1/7] Verificando dependências        (jq, git, gh, Claude Code)
[2/7] Verificando autenticações       (GitHub CLI)
[3/7] Configurando integrações        (GitHub MCP, Jira MCP — pede email + token)
[4/7] Instalando skills e commands    (copia para ~/.claude/)
[5/7] Configurando knowledge-service  (Gemini API key para embeddings)
[6/7] Iniciando knowledge-service     (Docker: PostgreSQL + pgvector)
[7/7] Finalizando                     (salva versão)
```

### Pré-requisitos

| Dependência | Obrigatório | Para que |
|---|---|---|
| [Git](https://git-scm.com/) | Sim | Worktrees, clone, commits, PRs |
| [Claude Code](https://claude.ai/code) | Sim | Runtime do agente |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Sim | PRs, CI, MCP do GitHub |
| [jq](https://jqlang.github.io/jq/) | Sim | Parsing de JSON nos scripts |
| [uv](https://docs.astral.sh/uv/) (uvx) | Recomendado | MCP do Atlassian (alternativa: npx ou Docker) |
| [Docker](https://docker.com) | Opcional | Knowledge-service (busca semântica e aprendizados compartilhados) |

### Atualizar

```bash
./install.sh --update       # Mac/Linux
.\install.ps1 -Update       # Windows
```

---

## Início rápido

Do zero ao primeiro uso em 4 passos:

```bash
# 1. Instale (uma vez — guia interativo de ~3 minutos)
git clone https://github.com/wallacehenriquesilva/ai-engineer.git
cd ai-engineer
./install.sh

# 2. Verifique que está tudo OK
make check
```

O `make check` valida tudo de uma vez:

```
AI Engineer — Diagnóstico do Ambiente
═══════════════════════════════════════

Dependências
  ✓ jq
  ✓ Claude Code
  ✓ GitHub CLI (gh)
  ✓ uvx (uv)
  ✓ Docker

Autenticação
  ✓ GitHub autenticado (your-github-user)

MCPs (integrações)
  ✓ GitHub MCP
  ✓ Atlassian MCP (Jira)

Skills e Commands
  ✓ 7 skills instaladas
  ✓ 7 commands instalados

Knowledge Service
  ✓ Knowledge-service rodando
  ✓ 47 repos indexados

═══════════════════════════════════════
  ✓ 12  ! 0  ✗ 0  (total: 12)

  Ambiente pronto! Execute: claude → /engineer --dry-run
```

```bash
# 3. Vá para a raiz dos seus repositórios e abra o Claude Code
cd ~/git
claude

# 4. Teste sem risco (na primeira vez, configura o time automaticamente)
/engineer --dry-run
```

Se o dry-run funcionar, execute de verdade:

```
/engineer
```

> **Sem Docker?** O agente funciona normalmente. Apenas busca semântica e aprendizados compartilhados ficam indisponíveis. O `make check` mostra o que está ativo e o que não.

---

## Uso

### Configuração do time (primeira vez)

Na primeira execução, o agente pergunta as configurações do time e gera um `CLAUDE.md`:

- Board e projeto do Jira
- Label que marca tasks para o agente
- Organização e time de revisão no GitHub
- Bot do SonarQube
- Guardrails (budget, clareza mínima, circuit breaker)

### Simulação (recomendado para começar)

```
/engineer --dry-run
```

Faz tudo — busca task, avalia clareza, analisa repo, planeja, gera código — mas **não cria branch, não abre PR, não move task**. Mostra exatamente o que faria.

### Implementar uma task

```
/engineer
```

Ciclo completo: Jira → implementa → testa → PR → CI → move task.

### Ciclo completo com deploy

```
/run
```

Engineer → resolve comentários de PR → deploy (sandbox → homolog → produção).

### Múltiplas tasks em paralelo

```
/run-parallel --workers 3
```

Busca N tasks, reserva todas, lança agentes paralelos em worktrees isolados.

### Resolver comentários de revisão

```
/pr-resolve https://github.com/org/repo/pull/123
```

Monitora PR, classifica comentários, implementa mudanças, responde dúvidas, aguarda aprovação.

### Histórico de execuções

```
/history --stats          # estatísticas dos últimos 30 dias
/history --limit 10       # últimas 10 execuções
/history --status failure # apenas falhas
```

### Gerar CLAUDE.md de um repositório

```
/init
```

Analisa o repo (stack, estrutura, testes, comandos, env vars) e gera um `CLAUDE.md` com as convenções detectadas. Executado automaticamente pelo `/engineer` quando o repo não tem `CLAUDE.md`.

---

## Guardrails

O agente tem mecanismos de segurança configuráveis no `CLAUDE.md` do time:

| Guardrail | Padrão | O que faz |
|---|---|---|
| **Dry-run** | `--dry-run` | Simula sem executar ações destrutivas |
| **Budget limit** | $5.00 | Interrompe se o custo da sessão ultrapassar o limite |
| **Confidence threshold** | 15/18 | Não implementa se a clareza da task for menor que o mínimo |
| **Circuit breaker** | 3 falhas | Para de pegar tasks se as últimas N execuções falharam |
| **Merge automático** | PR aprovada + homolog OK | Merge só acontece se um humano aprovou a PR e homolog validou |
| **Rollback** | Automático | Executa revert automaticamente se o deploy em produção falhar |

### CI/CD Pipeline configurável

Cada time configura seu fluxo de CI/CD no `CLAUDE.md`. O agente lê e adapta:

| Trigger | O que o agente faz |
|---|---|
| `auto` | Não faz nada — CI roda sozinho, agente só aguarda |
| `comment:/ok-to-test` | Posta o comentário na PR para disparar |
| `merge:develop` | Faz merge para a branch alvo |
| `skip` | Pula a etapa inteira |

Exemplo para CI automático sem ambientes intermediários:
```markdown
### Testes
- Trigger: `auto`
- Validação: `checks:*`
### Sandbox
- Trigger: `skip`
### Homolog
- Trigger: `skip`
```

---

## Multi-repo

Quando uma task envolve múltiplos repositórios (ex: backend + frontend), o agente coordena:

```
1. Classifica repos: Producer (API) → Consumer (frontend)
2. Implementa o Producer primeiro
3. Exporta o contrato (endpoints, payloads)
4. Sobe o Producer localmente
5. Implementa o Consumer usando o contrato
6. Testa o Consumer contra o Producer real (localhost)
7. Abre PRs referenciando uma à outra
```

---

## Aprendizado compartilhado

Agentes em diferentes máquinas compartilham aprendizados via knowledge-service:

```
Agente A falha: "mock desatualizado ao adicionar campo no model"
                          │
                          ▼
              ┌──────────────────────┐
              │  Knowledge Service   │
              │  (PostgreSQL+pgvector)│
              │                      │
              │  pattern registrado  │
              │  times_seen: 1       │
              └──────────┬───────────┘
                         │
Agente B consulta antes de implementar:
  "⚠️ Aprendizado: verificar mocks ao alterar models (visto 3x)"
```

Quando um pattern atinge `times_seen >= 3`, é listado para promoção ao `CLAUDE.md` do repo.

---

## Flags

| Flag | Comando | O que faz |
|---|---|---|
| `--dry-run` | `/engineer` | Simula sem criar branch, PR ou mover task |
| `--budget 10.00` | `/engineer` | Define limite de custo para a sessão |
| `--force` | `/engineer` | Ignora circuit breaker |
| `--workers 3` | `/run-parallel` | Número de tasks em paralelo (máx: 5) |
| `--stats` | `/history` | Mostra estatísticas agregadas |
| `--status failure` | `/history` | Filtra por status |
| `--limit 10` | `/history` | Limita número de resultados |

---

## Estrutura do repositório

```
ai-engineer/
├── commands/
│   ├── engineer.md               # implementação de task
│   ├── init.md                   # gera CLAUDE.md do repo
│   ├── pr-resolve.md             # resolução de comentários de PR
│   ├── finalize.md               # deploy e merge
│   ├── run.md                    # ciclo completo
│   ├── run-parallel.md           # execução paralela
│   └── history.md                # histórico e estatísticas
├── skills/
│   ├── jira-integration/         # operações no Jira
│   ├── jira-task-clarity/        # avaliação de clareza
│   ├── git-workflow/             # worktree, commits, PR, CI
│   ├── execution-feedback/       # aprendizado entre execuções
│   └── knowledge-query/          # busca semântica
├── scripts/
│   ├── execution-log.sh          # log de execuções (remoto + fallback local)
│   ├── knowledge-client.sh       # client para o knowledge-service
│   ├── run-parallel.sh           # worker pool
│   ├── org-scan.sh               # carga inicial do knowledge base
│   └── org-watch.sh              # atualização delta
├── knowledge-service/            # API Go (pgvector + Gemini embeddings)
├── tests/
│   ├── test-skills.sh            # 142 checks de estrutura
│   ├── test-execution-log.sh     # 15 checks do execution-log
│   └── main_test.go              # 16 testes Go (knowledge-service)
├── .mcp.json                     # MCPs do projeto (GitHub + Atlassian)
├── .claude-plugin/plugin.json    # manifesto do plugin
├── .github/workflows/            # CI (testes + release automático)
├── VERSION                       # versão atual
├── CHANGELOG.md                  # histórico de mudanças
├── CONTRIBUTING.md               # guia de contribuição
└── SECURITY.md                   # política de segurança
```

---

## Testes

```bash
make test-all        # roda tudo (Go + skills + execution-log)
make test-skills     # 142 checks de estrutura
make test-exec-log   # 15 checks do execution-log
make test            # testes Go do knowledge-service
```

---

## Criando uma nova skill

Skills são o conhecimento do agente. Cada skill ensina o agente a trabalhar com uma stack, ferramenta ou domínio específico.

### Estrutura

```
skills/<nome-da-skill>/
├── SKILL.md              # obrigatório — instruções para o agente
├── examples/             # opcional — código de referência
└── references/           # opcional — docs auxiliares
```

### SKILL.md

```markdown
---
name: minha-skill
description: >
  Descreva quando o agente deve acionar esta skill.
  Seja específico — o agente usa esta descrição para decidir.
context: default
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
---

# Nome da Skill

Instruções detalhadas para o agente...
```

| Campo | Obrigatório | Descrição |
|---|---|---|
| `name` | Sim | Identificador único |
| `description` | Sim | Quando acionar — o agente lê isso para decidir |
| `allowed-tools` | Sim | Ferramentas que a skill pode usar |

### O que incluir

**Skills de stack** (Go, React, Java): arquitetura, convenções, comandos, testes, exemplos, checklist.

**Skills de ferramenta** (Terraform, Docker): padrões, módulos, convenções, exemplos.

**Skills de processo** (git-workflow, jira-integration): fluxo passo a passo, regras, formato de output.

### Instalar e validar

```bash
make install-skills    # instala no Claude Code
make test-skills       # valida estrutura e referências
```

### Roteamento automático

O agente escolhe a skill com base no repositório:

| Indicador no repo | Skill acionada |
|---|---|
| `go.mod` | skill Go (se existir) |
| `package.json` + Next.js/React | skill frontend (se existir) |
| Nome termina com `-infra` | skill infra (se existir) |
| `pom.xml` ou `build.gradle` | skill Java (se existir) |
| Nenhum match | Gera `CLAUDE.md` via `/init` e usa conhecimento genérico |

---

## Contribuindo

PRs são bem-vindas! Veja [CONTRIBUTING.md](CONTRIBUTING.md) para detalhes.

## Licença

MIT — veja [LICENSE](LICENSE) para detalhes.
