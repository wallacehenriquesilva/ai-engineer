---
name: knowledge-query
version: 1.0.0
description: >
  Consulta o knowledge base centralizado da org para encontrar informações
  sobre repositórios, serviços, dependências e padrões arquiteturais.
  Use quando precisar saber em qual repo trabalhar, como um serviço funciona,
  quais endpoints ele expõe, ou quais variáveis de ambiente usa.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /knowledge-query
context: default
allowed-tools:
  - Bash
---

# Knowledge Query

Consulta o knowledge base vetorial centralizado da org.

## Endpoint

```
KNOWLEDGE_SERVICE_URL (padrão: http://localhost:8080)
```

Leia a URL do CLAUDE.md ou use o padrão.

## 1. Busca semântica (uso principal)

```bash
KNOWLEDGE_URL="${KNOWLEDGE_SERVICE_URL:-http://localhost:8080}"

curl -s -X POST "$KNOWLEDGE_URL/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "<descreva o que você quer saber em linguagem natural>",
    "top_k": 5
  }' | jq -r '.results[] | "## \(.repo) — \(.section)\n\(.content)\n"'
```

## 2. Filtrar por repo específico

```bash
curl -s -X POST "$KNOWLEDGE_URL/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "<sua query>",
    "top_k": 3,
    "repo": "<nome-do-repo>"
  }' | jq -r '.results[] | "## \(.repo) — \(.section)\n\(.content)\n"'
```

## 3. Ver todos os repos indexados

```bash
curl -s "$KNOWLEDGE_URL/repos" | jq -r '.[] | "\(.repo) (\(.lang)) — \(.chunks) chunks — atualizado: \(.last_updated)"'
```

## 4. Verificar saúde do serviço

```bash
curl -s "$KNOWLEDGE_URL/health" | jq .
```

## Como usar no fluxo de implementação

Antes de decidir em qual repo trabalhar, faça uma query com o contexto da task:

```bash
curl -s -X POST "$KNOWLEDGE_URL/query" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": \"<resumo da task do Jira>\",
    \"top_k\": 5
  }" | jq -r '.results[] | "[\(.score | . * 100 | round)%] \(.repo) — \(.section)\n\(.content | .[0:300])\n"'
```

Interprete os resultados:
- **Score > 0.85** — repo muito provavelmente relevante
- **Score 0.70–0.85** — repo possivelmente relevante, verifique o conteúdo
- **Score < 0.70** — provavelmente não é o repo certo

## 5. Buscar aprendizados (semântico)

Busca learnings compartilhados entre agentes relevantes ao contexto:

```bash
curl -s -X POST "$KNOWLEDGE_URL/learnings/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "<descreva o que pretende implementar>",
    "repo": "<repo-opcional>",
    "top_k": 5,
    "unresolved_only": true
  }' | jq -r '.[] | "⚠️ [\(.pattern)] (visto \(.times_seen)x): \(.solution)"'
```

## 6. Candidatos a promoção

Learnings com `times_seen >= 3` que devem ser avaliados para inclusão no CLAUDE.md do repo:

```bash
curl -s "$KNOWLEDGE_URL/learnings/promotions" | jq -r '.[] | "\(.repo) — \(.pattern) (visto \(.times_seen)x): \(.solution)"'
```

## 7. Estatísticas de execuções do time

```bash
curl -s "$KNOWLEDGE_URL/executions/stats?days=30" | jq .
```

## 8. Histórico de execuções

```bash
curl -s "$KNOWLEDGE_URL/executions?limit=20&status=failure" | jq -r '.[] | "[\(.status)] \(.started_at | .[0:10]) \(.command) \(.task) \(.repo) — \(.failure_reason // "ok")"'
```

## Regras

- Sempre consulte antes de assumir o repo correto
- Se o serviço não estiver disponível (`curl` falhar), use o `_index.md` local como fallback
- Não armazene resultados em disco — consulte sempre fresh
- Aprendizados são compartilhados entre todos os agentes do time — consulte antes de implementar