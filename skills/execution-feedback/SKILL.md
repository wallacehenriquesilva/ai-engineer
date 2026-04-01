---
name: execution-feedback
version: 1.0.0
description: >
  Registra aprendizados de execuções passadas (falhas, padrões de erro, soluções)
  no knowledge-service centralizado e os consulta antes de novas implementações.
  Aprendizados são compartilhados entre todos os agentes do time.
  Acione esta skill quando uma execução falhar para registrar o aprendizado,
  ou antes de iniciar uma implementação para consultar falhas anteriores em repos similares.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /execution-feedback
context: default
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# Execution Feedback — Aprendizado Compartilhado Entre Agentes

Registra e consulta aprendizados de execuções passadas via knowledge-service centralizado.
Todos os agentes do time compartilham os mesmos aprendizados.

---

## Pré-requisito

```bash
source scripts/knowledge-client.sh
```

O client usa `KNOWLEDGE_SERVICE_URL` (default: `http://localhost:8080`) e `AGENT_ID` (default: hostname).

---

## A. Registrar Aprendizado (após falha)

Quando uma execução falhar, registre o aprendizado:

### Dados necessários

| Campo | Descrição | Exemplo |
|---|---|---|
| `repo` | Repositório onde ocorreu | `martech-integration-worker` |
| `task` | Chave da task | `AZUL-1234` |
| `step` | Etapa que falhou | `9` |
| `error_type` | Categoria do erro | `test_failure`, `ci_timeout`, `build_error`, `sonar_failure`, `deploy_failure` |
| `error_message` | Mensagem de erro resumida | `TestProcessLeadCreated falhou: mock não configurado para novo campo` |
| `root_cause` | Causa raiz identificada | `Campo adicionado no model sem atualizar o mock do teste existente` |
| `solution` | O que resolveu (ou resolveria) | `Ao adicionar campo em model, verificar todos os mocks que usam a struct` |
| `pattern` | Padrão generalizável | `model_change_without_mock_update` |

### Registrar

```bash
source scripts/knowledge-client.sh
kc_learning_create "$REPO" "$TASK" "$STEP" "$ERROR_TYPE" "$ERROR_MESSAGE" "$ROOT_CAUSE" "$SOLUTION" "$PATTERN"
```

O serviço automaticamente:
- Se o `pattern` já existir: incrementa `times_seen`
- Se for novo: gera embedding semântico e insere

---

## B. Consultar Aprendizados (antes de implementar)

### Busca semântica (recomendado)

Descreva o contexto da implementação em linguagem natural:

```bash
source scripts/knowledge-client.sh
kc_learning_search "consumer SQS para eventos de WhatsApp" "$REPO" 5
```

### Filtrar por repositório

```bash
kc_learning_list "$REPO"
```

### Apresentação

Quando aprendizados forem encontrados, apresente-os como avisos antes de implementar:

```
## Aprendizados relevantes para este repositório

⚠️ **model_change_without_mock_update** (visto 3x, 2 agentes)
   Ao adicionar campo em model, verificar todos os mocks que usam a struct.
   Última ocorrência: AZUL-1234 (2026-03-25)

⚠️ **missing_env_var_in_config** (visto 2x)
   Novas env vars devem ser adicionadas tanto em config.go quanto em values.yaml.
   Última ocorrência: AZUL-1180 (2026-03-20)
```

---

## C. Marcar como Resolvido

Quando um padrão for corrigido estruturalmente:

```bash
source scripts/knowledge-client.sh
kc_learning_resolve "$LEARNING_ID"
```

---

## D. Auto-Promoção para CLAUDE.md

Consulte learnings candidatos a promoção (`times_seen >= 3`, não promovidos):

```bash
source scripts/knowledge-client.sh
kc_learning_promotions
```

Para cada candidato:
1. Avalie se a solução é generalizável
2. Se sim, adicione como regra permanente no `CLAUDE.md` do repo ou na skill relevante
3. Marque como promovido no serviço

---

## E. Estatísticas

```bash
source scripts/knowledge-client.sh
kc_exec_stats 30
```

---

## Integração com o Ciclo de Implementação

1. **Antes da Etapa 7 (Implementar) do `/engineer`:** consulte aprendizados para o repo alvo via `kc_learning_search` e inclua os avisos no plano.

2. **No "Em Caso de Falha" do `/engineer`:** registre o aprendizado via `kc_learning_create`.

---

## Regras

- Deduplicação é automática — o serviço incrementa `times_seen` por pattern.
- Learnings com `times_seen >= 3` devem ser avaliados para promoção ao CLAUDE.md do repo.
- O campo `solution` deve ser acionável — descreva o que fazer, não apenas o que deu errado.
- Busca semântica permite encontrar learnings por contexto, não só por nome de repo.
- Esta skill não implementa código e não move tasks.
