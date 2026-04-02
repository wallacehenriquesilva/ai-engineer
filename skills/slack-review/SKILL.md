---
name: slack-review
version: 1.0.0
description: >
  Envia pedidos de code review e respostas em threads no Slack via MCP.
  SEMPRE acione esta skill quando o usuário quiser pedir review de uma PR no Slack,
  responder comentários de revisão, notificar revisores, ou quando qualquer fluxo
  de engenharia precisar comunicar sobre code review — mesmo que o usuário não
  mencione "Slack" explicitamente. Exemplos: "pede review dessa PR", "avisa que
  resolvi os comentários", "manda pro time revisar", "notifica o time da PR".
  Uso: /slack-review <ação> <argumentos>
depends-on: []
triggers:
  - user-command: /slack-review
  - called-by: engineer
  - called-by: pr-resolve
  - called-by: finalize
allowed-tools:
  - Bash
  - Read
  - mcp__claude_ai_Slack__*
  - mcp__github__*
---

# slack-review: Code Review no Slack

Comunica pedidos de code review e respostas de revisão no Slack, conectando o
fluxo do GitHub com a comunicação do time. Isso é importante porque reviews que
ficam só no GitHub tendem a ser ignoradas — uma mensagem no Slack garante
visibilidade e agiliza o feedback.

## Detecção de Ação

Analise `$ARGUMENTS` ou o contexto da conversa para determinar a ação:

| Intenção do usuário | Ação |
|---|---|
| Pedir review, enviar PR pro time, "manda review" | `request` |
| Responder thread, "resolvi os comentários", "avisa o revisor" | `reply` |

Se a intenção não estiver clara, pergunte ao usuário.

---

## Etapa 0 — Pré-condições

### Verificar ferramentas MCP

Antes de qualquer ação, confirme que as tools do Slack estão disponíveis tentando
listar canais com `slack_list_channels` (limit=1). Se falhar com erro de
autenticação ou tool não encontrada, oriente o usuário:

> **Erro:** Slack MCP não está configurado ou autenticado.
> Verifique se o MCP do Slack está ativo nas configurações do Claude Code.

Essa verificação evita erros confusos no meio do fluxo — é melhor falhar cedo
com uma mensagem clara do que depois de já ter coletado dados da PR.

### Carregar configurações do CLAUDE.md

Leia as configurações do `CLAUDE.md` do diretório atual:

```bash
SLACK_REVIEW_CHANNEL=$(grep "Slack Review Channel:" CLAUDE.md | awk '{print $NF}')
```

Se a variável estiver vazia ou o `CLAUDE.md` não existir, informe ao usuário:

> **Erro:** Canal de review não configurado. Adicione ao seu `CLAUDE.md`:
> ```
> Slack Review Channel: C0XXXXXXXX
> ```

O usuário também pode informar o canal diretamente via argumento (ex: `#meu-canal`),
que tem prioridade sobre o configurado.

---

## Resolução de Usuários — GitHub para Slack

Resolver quem é quem entre GitHub e Slack é o passo mais delicado desta skill.
A API do Slack tem rate limits agressivos (~20 requests/minuto para `users.list`),
então paginar repetidamente é caro e lento. Por isso, a skill usa uma estratégia
em camadas — do mais eficiente para o menos.

### Camada 1: Mapa fixo no CLAUDE.md (preferencial)

O usuário pode configurar um mapa de GitHub login → Slack User ID no CLAUDE.md.
Isso elimina chamadas à API e é 100% confiável:

```markdown
## Slack User Map
- wallace.silva: U0ABC123
- joao.dev: U0DEF456
- maria.front: U0GHI789
```

Leia este mapa com:

```bash
grep -A100 "## Slack User Map" CLAUDE.md | grep "^-" | head -50
```

### Camada 2: Grupos de review por tipo de task

Para a ação `request`, em vez de mencionar reviewers individuais, o usuário
pode configurar grupos por tipo de trabalho. Isso é útil quando o time tem
especialidades (backend, frontend, infra) e o pedido de review deve ir para
o grupo certo:

```markdown
## Slack Review Groups
- backend: @martech-backends
- frontend: @martech-frontends
- infra: @martech-team
- default: @martech-team
```

**Como usar os grupos:**

1. Detecte o tipo da task pelos arquivos alterados na PR ou por labels
2. Busque o grupo correspondente no mapa
3. Use o grupo na mensagem de `request` em vez de listar reviewers individuais
4. Se não encontrar grupo específico, use `default`

Os valores podem ser Slack User Group handles (ex: `@martech-backends`) ou
User Group IDs (ex: `S0ABC123`). Se for handle, use `<!subteam^S0ABC123|@handle>`
na mensagem para fazer a menção funcionar.

**Importante:** Os grupos são usados apenas na ação `request` para notificar o
time certo. Na ação `reply`, a menção é sempre individual — responde-se
diretamente ao revisor que fez o comentário, não ao grupo.

### Camada 3: Busca na API do Slack (fallback)

Use apenas quando o usuário não estiver no mapa fixo (Camada 1). Isso acontece
principalmente na ação `reply`, quando precisamos mencionar um revisor específico
que comentou na PR.

1. Pagine `slack_get_users` (limit=200) — faça no máximo 3 páginas (600 usuários)
2. Match por `name` do Slack com o login do GitHub (ex: `wallace.silva`)
3. Se não encontrar, tente por `real_name`
4. Se após 3 páginas não encontrar, use o nome em texto plano (sem @mention)

Mantenha um cache local durante a execução para não repetir buscas. Se encontrar
o usuário, sugira ao usuário que adicione o ID ao mapa do CLAUDE.md para evitar
buscas futuras.

---

## Ação: `request`

**Sintaxe:** `/slack-review request <PR-URL> [#canal]`

### Passo 1 — Extrair dados da PR

Obtenha via GitHub MCP:

- **Título** e **descrição** da PR
- **Autor** (quem abriu)
- **Reviewers solicitados** (requested_reviewers)
- **Labels** da PR (útil para determinar o grupo de review)
- **Arquivos alterados** (lista resumida)
- **Repo** e **número da PR**

### Passo 2 — Identificar o canal

Prioridade:
1. Canal informado pelo usuário via argumento (`#canal`)
2. Canal configurado no `CLAUDE.md` (`$SLACK_REVIEW_CHANNEL`)

Para encontrar o ID de um canal pelo nome, pagine `slack_list_channels` buscando pelo `name`.

### Passo 3 — Verificar duplicatas

Antes de enviar, busque nas últimas 50 mensagens do canal se já existe uma mensagem
com a mesma PR-URL. Se existir, informe ao usuário e pergunte se deseja enviar
mesmo assim. Isso evita spam no canal quando a skill é acionada mais de uma vez
para a mesma PR (ex: por integração automática com `/engineer`).

### Passo 4 — Resolver menções

1. Resolva o autor da PR usando a estratégia de camadas (mapa → API)
2. Para reviewers, verifique primeiro se há grupos configurados (Camada 2):
   - Detecte o tipo pelo label da PR ou pelos arquivos alterados (`.go` → backend, `.tsx` → frontend, `.tf` → infra)
   - Se encontrar grupo, use-o na mensagem
3. Se não houver grupos, resolva reviewers individuais pela estratégia de camadas

### Passo 5 — Enviar mensagem

Envie no canal usando `slack_post_message`.

Leia `references/message-templates.md` para os templates padrão. Se o CLAUDE.md
tiver uma seção `## Slack Review Templates`, use o template customizado.

### Passo 6 — Confirmar envio e salvar ts

Após enviar, o `slack_post_message` retorna um `ts` (timestamp). Este `ts` é o ID da mensagem e será usado para responder na thread.

**Sempre retorne o `ts` no output** para que a skill chamadora possa salvá-lo:

```
Mensagem enviada!
Canal: #<nome-do-canal>
Timestamp: <ts>
PR: <PR-URL>
```

O `/engineer` (Etapa 12.6) salva este `ts` no work queue via `wq_set_slack_ts` para uso em replies futuros.

---

## Ação: `reply`

**Sintaxe:** `/slack-review reply <PR-URL> [mensagem personalizada]`

Responde na thread da mensagem de review original informando que comentários
foram resolvidos. Aqui a menção é sempre individual — quem comentou precisa
receber a notificação diretamente.

### Passo 1 — Localizar a mensagem original

Primeiro, tente recuperar o `ts` do work queue (salvo pelo `/engineer` na Etapa 12.6):

```bash
source ~/.ai-engineer/scripts/work-queue.sh
THREAD_TS=$(wq_get_slack_ts "$TASK_ID" "$REPO_NAME")
```

Se `$THREAD_TS` estiver preenchido → use-o diretamente como `thread_ts`. Pule a busca no histórico.

Se `$THREAD_TS` estiver vazio → fallback: busque no canal configurado (`$SLACK_REVIEW_CHANNEL`)
usando `slack_get_channel_history` e encontre a que contém a `<PR-URL>`.

- Busque em lotes: primeiro 50 mensagens, depois mais 50 se não encontrar (até 200)
- Identifique pelo link da PR no texto
- Extraia o `ts` (será o `thread_ts`)

Se não encontrar após 200 mensagens, informe ao usuário. Ele pode fornecer o `ts`
diretamente ou indicar outro canal.

### Passo 2 — Extrair dados da PR

Obtenha do GitHub:

- **Últimos comentários de review** resolvidos
- **Quem fez os comentários** (revisores — precisamos dos nomes para menção individual)
- **Status da PR** (aberta, aprovada, merged)

### Passo 3 — Resolver User IDs dos revisores

Resolva os Slack User IDs dos revisores que fizeram comentários usando a estratégia
de camadas. Como `reply` precisa de menções individuais (não de grupo), use:

1. Primeiro o mapa fixo do CLAUDE.md (Camada 1)
2. Se não estiver no mapa, busque na API (Camada 3)

### Passo 4 — Responder na thread

Use `slack_reply_to_thread` com o `thread_ts` da mensagem original.

**Se o usuário forneceu mensagem personalizada**, use-a como base e adicione as
menções dos revisores.

**Se não forneceu**, gere uma resposta usando o template de `references/message-templates.md`.

Se houver múltiplos revisores, mencione todos.

---

## Integração com outras skills

Leia `references/integration-guide.md` para detalhes sobre como esta skill se
conecta com `/engineer`, `/pr-resolve` e `/finalize`. A integração automática
pode ser habilitada com `Slack Auto Review: true` no CLAUDE.md.

---

## Regras Gerais

- Use `<@USER_ID>` para mencionar usuários sempre que o ID for conhecido — isso
  garante que a pessoa receba a notificação no Slack
- Use `<!subteam^GROUP_ID|@handle>` para mencionar grupos de usuários
- Mensagens devem ser concisas e profissionais
- Use emojis de forma consistente com o padrão dos templates
- Respostas em thread mencionam o revisor individual para que ele receba notificação
- Ao responder comentários, seja específico sobre o que foi feito (cite commits quando possível)
- Se encontrar um usuário via API que não estava no mapa, sugira ao usuário adicioná-lo ao CLAUDE.md
