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
source ~/.ai-engineer/scripts/knowledge-client.sh
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
source ~/.ai-engineer/scripts/knowledge-client.sh
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
source ~/.ai-engineer/scripts/knowledge-client.sh
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
source ~/.ai-engineer/scripts/knowledge-client.sh
kc_learning_resolve "$LEARNING_ID"
```

---

## D. Auto-Promoção para CLAUDE.md

Após cada execução bem-sucedida, verifique se há aprendizados prontos para promoção.

### D1. Buscar candidatos

```bash
source ~/.ai-engineer/scripts/knowledge-client.sh
CANDIDATES=$(kc_learning_promotions)
```

Se vazio ou knowledge-service indisponível → pule silenciosamente.

### D2. Filtrar por repo atual

Filtre os candidatos pelo repo onde a execução aconteceu:

```bash
echo "$CANDIDATES" | jq --arg repo "$REPO" '[.[] | select(.repo == $repo)]'
```

Se nenhum candidato para este repo → pule.

### D3. Gerar regra para o CLAUDE.md

Para cada candidato, gere uma regra concisa e acionável baseada no campo `solution`:

```
## Convenções (auto-promovidas)

- <solução do learning> (padrão: <pattern>, visto <times_seen>x)
```

**Critérios para promoção:**
- A solução deve ser **generalizável** (não específica de uma task)
- A solução deve ser **acionável** (descreve o que fazer, não só o que deu errado)
- Se a solução é muito específica (ex: "corrigir typo no campo X") → **não promover**

### D4. Abrir PR com a regra

1. Crie branch: `chore/promote-learning-<pattern>`
2. Edite o `CLAUDE.md` do repo, adicionando a regra na seção de convenções
3. Abra PR:
   - Título: `chore: promote learning — <pattern>`
   - Body: explique que o padrão foi visto N vezes, descreva o aprendizado original
   - Labels: `ai-first`, `chore`
4. **NÃO faça merge automático** — a PR requer aprovação humana

### D5. Marcar como promovido

Após abrir a PR, marque o learning como promovido no knowledge-service:

```bash
kc_learning_promote "$LEARNING_ID"
```

Isso evita que o mesmo learning seja promovido novamente.

### D6. Fallback sem knowledge-service

Se o knowledge-service estiver indisponível, a auto-promoção é pulada silenciosamente. O fluxo principal (implementação) nunca deve falhar por causa da promoção.

---

## E. Estatísticas

```bash
source ~/.ai-engineer/scripts/knowledge-client.sh
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
