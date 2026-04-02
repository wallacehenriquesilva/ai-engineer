---
name: jira-integration
version: 1.0.0
description: >
  Interage com o Jira para operações em tasks de qualquer board.
  Acione esta skill quando o usuário quiser: buscar a próxima task disponível para implementação,
  ver detalhes de uma task específica (ex: "me mostra a AZUL-1234"),
  mover uma task de status (ex: "move pra Done", "coloca em code review"),
  ou adicionar um comentário em uma task.
  Também acione quando o usuário perguntar "qual a próxima task?", "tem task pra pegar?",
  "próxima task de backend", ou mencionar qualquer operação no Jira.
depends-on: []
triggers:
  - called-by: engineer
  - called-by: run-parallel
  - user-command: /jira-integration
context: default
allowed-tools:
  - Bash
  - mcp__mcp-atlassian__jira_get_board_sprints
  - mcp__mcp-atlassian__jira_search_issues
  - mcp__mcp-atlassian__jira_get_issue
  - mcp__mcp-atlassian__jira_get_issue_transitions
  - mcp__mcp-atlassian__jira_get_transitions
  - mcp__mcp-atlassian__jira_transition_issue
  - mcp__mcp-atlassian__jira_add_comment
---

# Jira Integration

Esta skill gerencia operações no Jira. Identifique qual(is) operação(ões) o usuário quer e siga a(s) seção(ões) correspondente(s).

## Resolução do Board ID

Antes de executar qualquer operação que dependa de um board (Seção A), resolva o `boardId`:

1. **Usuário informou na mensagem** (ex: "próxima task do board 2081", "tasks do board 3055") → use o valor informado.
2. **Contexto da conversa já tem um board** (ex: uma operação anterior nesta sessão usou um board) → reutilize o mesmo.
3. **Nenhum dos anteriores** → pergunte: **"Qual o Board ID do Jira? (ex: 2081)"** e aguarde a resposta antes de prosseguir.

> Para operações que não dependem de board (Seções B, C, D), pule esta resolução.

---

- **"próxima task"**, **"tem task pra pegar?"** → Seção A
- **ID de task específica** (ex: "AZUL-1234", "me mostra a XYZ-99") → Seção B
- **"move para..."**, **"coloca em..."** → Seção C
- **"comenta na task"**, **"adiciona um comentário"** → Seção D

### Operações compostas

O usuário pode pedir múltiplas operações em uma única mensagem (ex: "pega a próxima task e comenta que estou começando", "me mostra a AZUL-1234 e move pra fazendo"). Nesse caso, execute cada operação em sequência na ordem natural: buscar/identificar a task primeiro, depois agir sobre ela (mover, comentar). Use o resultado de uma operação como entrada para a próxima — por exemplo, se o usuário pede "próxima task e comenta X", use a task retornada pela Seção A como alvo da Seção D.

---

## A. Buscar Próxima Task Disponível

### A1. Buscar sprint ativa

Use `jira_get_board_sprints` com o `boardId` resolvido na seção "Resolução do Board ID" e `state: active`.
Extraia o `sprintId`. Se houver mais de uma sprint ativa, use a de maior `id`.
Se não houver sprint ativa, encerre com: **"Nenhuma sprint ativa encontrada no board <boardId>."**

### A2. Listar tasks disponíveis

Use `jira_search_issues` com o JQL:

```
sprint = <sprintId> AND status in ("To Do", "A Fazer") AND labels = "<AI_LABEL>" ORDER BY priority DESC, created ASC
```

Campos obrigatórios: `summary`, `description`, `customfield_13749`, `labels`, `issuelinks`, `subtasks`, `status`, `priority`, `assignee`.

Se nenhuma issue for retornada, encerre com: **"Nenhuma task com label AI disponível na sprint atual."**

### A3. Verificar bloqueios

**CRITICAL:** Esta verificação é obrigatória e não pode ser pulada. Pegar uma task bloqueada causa conflitos graves na sprint.

Para **cada** issue retornada na A2, inspecione o campo `issuelinks`. Uma issue está bloqueada se **qualquer** link satisfazer TODAS as condições:

1. O tipo do link é `"Blocks"` (ou `"is blocked by"` no campo `inwardIssue`)
2. A issue apontada pelo link (`inwardIssue`) **não** está em status `Done`, `Pronto`, `Closed` ou `Resolved`

Para cada link de bloqueio encontrado, use `jira_get_issue` para verificar o status atual da issue bloqueante. Não assuma o status pelo campo `issuelinks` — ele pode estar desatualizado.

```
Exemplo de issuelinks que BLOQUEIA:
{
  "type": {"name": "Blocks", "inward": "is blocked by"},
  "inwardIssue": {"key": "AZUL-8888", "fields": {"status": {"name": "In Progress"}}}
}
→ AZUL-8888 está "In Progress" (não Done) → task está BLOQUEADA → DESCARTAR

Exemplo de issuelinks que NÃO bloqueia:
{
  "type": {"name": "Blocks", "inward": "is blocked by"},
  "inwardIssue": {"key": "AZUL-7777", "fields": {"status": {"name": "Done"}}}
}
→ AZUL-7777 está "Done" → bloqueio resolvido → task DISPONÍVEL
```

**Também verifique `outwardIssue` com tipo `"is blocked by"`** — dependendo da configuração do Jira, o bloqueio pode aparecer em qualquer direção do link.

Se a issue tem bloqueio ativo → **descarte** e passe para a próxima da lista.

Se **todas** as issues estiverem bloqueadas, encerre com: **"Todas as tasks AI da sprint estão bloqueadas."**

### A4. Selecionar a task

Pegue **apenas a primeira** issue válida da lista (já ordenada por prioridade).

### A5. Mover para "Fazendo"

Execute este passo ANTES de retornar qualquer dado.

Use `jira_get_issue_transitions` para obter as transições disponíveis.
Identifique o `transitionId` de `Fazendo` ou `In Progress`.
Execute `jira_transition_issue` com esse `transitionId`.

Se a issue já estiver em `Fazendo` / `In Progress`, pule este passo.

### A6. Retornar os dados

Use o formato da Seção E.

---

## B. Buscar Task Específica

Quando o usuário fornece um ID de task (ex: "AZUL-1234"):

1. Use `jira_get_issue` com a chave fornecida. Solicite os campos: `summary`, `description`, `customfield_13749`, `labels`, `issuelinks`, `subtasks`, `status`, `priority`, `assignee`.
2. Apresente usando o formato da Seção E.
3. **Não mova** a task de status — apenas exiba os dados.

---

## C. Mover Task de Status

Quando o usuário pede para mover uma task (ex: "move AZUL-1234 para Done"):

1. Identifique a **chave da task** e o **status destino** na mensagem do usuário.
   - Se o usuário não especificar a task, pergunte qual.
   - Se o contexto da conversa tiver uma task recente, use essa.
2. Use `jira_get_issue_transitions` para listar transições disponíveis.
3. Encontre a transição que corresponde ao status pedido (match parcial e case-insensitive — ex: "done" casa com "Done", "review" casa com "Code Review").
4. Se encontrar, execute `jira_transition_issue`.
5. Confirme: **"Task <KEY> movida para <status>."**
6. Se a transição não estiver disponível, liste as transições possíveis e pergunte qual usar.

---

## D. Comentar em uma Task

Quando o usuário quer adicionar um comentário:

1. Identifique a **chave da task** e o **conteúdo do comentário**.
   - Se o usuário não especificar a task, pergunte qual.
   - Se o contexto da conversa tiver uma task recente, use essa.
2. Verifique se o comentário precisa **mencionar** alguém (nomes de pessoas, `$CLARITY_OWNERS`, etc.).

### D1. Comentário sem menções

Use `jira_add_comment` com a chave e o texto do comentário.

### D2. Comentário com menções

O MCP não suporta menções nativas. Use a API REST do Jira com ADF (Atlassian Document Format):

**Passo 1 — Resolver credenciais:**

```bash
source ~/.ai-engineer/.env
```

**Passo 2 — Buscar `accountId` de cada pessoa mencionada:**

```bash
curl -s -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  "$JIRA_URL/rest/api/3/user/search?query=<nome-ou-email>" \
  | jq '.[0] | {accountId, displayName}'
```

Se a busca retornar vazio, tente variações (primeiro nome, email, username). Se ainda assim não encontrar, use o nome como texto simples sem menção.

**Passo 3 — Montar o body ADF e enviar:**

```bash
curl -s -X POST \
  -u "$JIRA_USERNAME:$JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/3/issue/<TASK-KEY>/comment" \
  -d '<ADF_JSON>'
```

O ADF deve intercalar blocos `text` e `mention`. Exemplo com uma menção:

```json
{
  "body": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "paragraph",
        "content": [
          { "type": "text", "text": "[AI Engineer] Clareza: 11/18\n\nSuposições listadas acima. " },
          {
            "type": "mention",
            "attrs": { "id": "<accountId>", "text": "@Display Name" }
          },
          { "type": "text", "text": " por favor valide." }
        ]
      }
    ]
  }
}
```

Para múltiplas menções, adicione um bloco `mention` para cada pessoa.

3. Confirme: **"Comentário adicionado na task <KEY>."**

---

## E. Formato de Apresentação

```
## Task: <issueKey> — <summary>

**Status:** <status atual>
**Prioridade:** <priority>
**Assignee:** <assignee ou "Não atribuído">

### Descrição
<Use `description` se preenchido. Caso contrário, use `customfield_13749`.
Se ambos estiverem preenchidos, apresente `description` como contexto principal
e `customfield_13749` como informação complementar.>

### Subtasks
<Se houver subtasks, liste cada uma com: chave, título e status.
Use `jira_get_issue` para buscar os detalhes de cada subtask individualmente.
Se não houver subtasks, omita esta seção.>

### Links
<Liste issues relacionadas com: chave, tipo de relação e status atual.
Se não houver links, omita esta seção.>

### Labels
<Lista de labels>
```

Para um exemplo de saída formatada, veja [examples/task-output.md](examples/task-output.md).

---

## Regras Gerais

- Esta skill apenas consulta e gerencia status/comentários no Jira. Não implementa código.
- Selecione **somente uma** task na operação "próxima task".
- Use as ferramentas MCP do Jira para operações padrão. Use a API REST diretamente (via `curl`) apenas para comentários com menções (Seção D2), que requerem ADF.