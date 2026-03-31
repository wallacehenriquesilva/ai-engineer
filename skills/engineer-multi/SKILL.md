---
name: engineer-multi
description: >
  Fluxo de implementação coordenada para tasks que envolvem 2+ repositórios.
  Carregado sob demanda pelo /engineer quando detecta múltiplos repos.
  Não deve ser chamado diretamente pelo usuário.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - mcp__github__*
---

# Fluxo Multi-Repo Coordenado

Quando 2+ repos são detectados na task, siga este fluxo em vez das Etapas 5–12 do `/engineer`.

## MR.1 — Classificar Repos por Papel

| Papel | Critério | Exemplos |
|---|---|---|
| **Producer** | Expõe API, endpoint ou evento | Backend Go, API REST, producer SNS |
| **Consumer** | Consome API, endpoint ou evento | Frontend Next.js, BFF, consumer SQS |
| **Infra** | Provisiona recursos | Repos `-infra` (Terraform) |

Ordem de implementação: **Infra → Producer → Consumer**.

Sem dependência clara entre repos → agentes paralelos direto.

## MR.2 — Setup de Todos os Repos

Para **cada** repo, em paralelo:

1. Verifique/crie `CLAUDE.md` do repo (`/init` se necessário)
2. Crie worktree: `/worktree create <TASK-ID>/<descricao-kebab-case>`
3. Commit vazio para DORA: `git commit -m 'chore: initial commit' --allow-empty && git push`

> **Dry-run:** registre o que faria mas não execute.

## MR.3 — Implementar Producer

Implemente o repo Producer primeiro (Etapas 7–9 do `/engineer`):

1. Analise e planeje — inclua o contrato que será exposto
2. Implemente — código, migrations, producers
3. Teste — `make test` (ou equivalente)

## MR.4 — Exportar Contrato

Salve em `.claude/contracts/contract-<TASK-ID>.md`:

```markdown
## Contrato — <TASK-ID>

### Endpoints
#### <METHOD> /v1/<path>
Request: ```json { ... } ```
Response (2xx): ```json { ... } ```

### Eventos SNS (se aplicável)
- Tópico: `<TOPIC_NAME>`
- Payload: `{ ... }`

### Variáveis de ambiente novas
- `<VAR>` — descrição
```

## MR.5 — Subir Producer Localmente

```bash
cd <producer-repo>
cd development-environment && make start && cd ..
make run &
PRODUCER_PID=$!
for i in $(seq 1 30); do curl -sf http://localhost:<PORT>/health && break; sleep 2; done
```

Se não subir, prossiga sem teste integrado — sinalize na PR.

> **Dry-run:** pule. Registre o que faria.

## MR.6 — Implementar Consumer

Implemente usando o contrato do MR.4 como referência (Etapas 7–9 do `/engineer`).

## MR.7 — Teste de Integração Cross-Repo

Com Producer rodando:

```bash
cd <consumer-repo>
export API_URL=http://localhost:<PRODUCER_PORT>
npm run test:integration 2>&1 || make test-integration 2>&1 || true
```

Sem suite de integração, faça smoke test via curl no endpoint do Producer.

> **Dry-run:** pule. Registre o que faria.

## MR.8 — Corrigir Incompatibilidades

Se teste falhar: identifique o repo, corrija, re-teste. Máximo 2 tentativas.

## MR.9 — Parar Producer

```bash
kill $PRODUCER_PID 2>/dev/null
cd <producer-repo>/development-environment && make stop 2>/dev/null
```

## MR.10 — Commits e PRs

Para cada repo:

1. Commits atômicos (`git-workflow` — Seção 2)
2. Abra PR (`git-workflow` — Seção 3)
3. PR do Consumer referencia PR do Producer como dependência
4. PR do Producer referencia PR do Consumer como relacionada
5. Labels e CI para ambas

Após MR.10, retome o `/engineer` na Etapa 12.1.
