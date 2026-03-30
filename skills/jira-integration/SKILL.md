---
name: jira-integration
description: >
  Interage com o Jira para operações em tasks de qualquer board.
  Acione esta skill quando o usuário quiser: buscar a próxima task disponível para implementação,
  ver detalhes de uma task específica (ex: "me mostra a AZUL-1234"),
  mover uma task de status (ex: "move pra Done", "coloca em code review"),
  ou adicionar um comentário em uma task.
  Também acione quando o usuário perguntar "qual a próxima task?", "tem task pra pegar?",
  "próxima task de backend", ou mencionar qualquer operação no Jira.
context: default
allowed-tools:
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

Para cada issue, inspecione `issuelinks`. Descarte a issue se houver qualquer link `inward` do tipo `"is blocked by"` cujo status da issue bloqueante **não seja** `Done` ou `Pronto`.

Use `jira_get_issue` para checar o status da issue bloqueante quando necessário.

Se todas as issues estiverem bloqueadas, encerre com: **"Todas as tasks AI da sprint estão bloqueadas."**

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
2. Use `jira_add_comment` com a chave e o texto do comentário.
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
- Sempre use as ferramentas MCP do Jira — nunca tente acessar a API diretamente.