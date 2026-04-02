---
name: pr-resolve
version: 1.1.0
description: >
  Monitora uma PR aberta, aguarda comentários do time de engenharia,
  aplica resoluções, responde revisores e acompanha até a aprovação final.
  Lê configurações do CLAUDE.md do diretório atual. Uso: /pr-resolve <PR-URL>
depends-on:
  - git-workflow
  - slack-review
triggers:
  - user-command: /pr-resolve
  - called-by: run
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - mcp__github__*
---

# pr-resolve: Resolução de Comentários de PR

## Flags

- `--no-poll` → Pula o polling da Etapa 3. Vai direto para Etapa 4 (analisar comentários existentes), resolve, faz push, e retorna. Usado pelo `/run-queue` para resolver feedback sem bloquear.

---

## Etapa 0 — Carregar Configurações

```bash
test -f CLAUDE.md && echo "exists" || echo "missing"
```

Se não existir: **"CLAUDE.md não encontrado. Execute /engineer primeiro."**

```bash
GITHUB_ORG=$(grep "GitHub Org:" CLAUDE.md | awk '{print $NF}')
SONAR_BOT=$(grep "Bot do SonarQube:" CLAUDE.md | awk '{print $NF}')
CI_MAX_RETRIES=$(grep "Máximo de tentativas:" CLAUDE.md | grep -oE '[0-9]+' | head -1 || echo "2")
SLACK_AUTO_REVIEW=$(grep "Slack Auto Review:" CLAUDE.md | awk '{print $NF}' || echo "false")
```

---

## Etapa 1 — Carregar Contexto da PR

```bash
gh pr view <PR-URL> --json title,body,headRefName,baseRefName,state,reviews,comments
gh pr diff <PR-URL> --name-only
gh pr checks <PR-URL>
```

Extraia:
- **Chave da task Jira** — do body da PR
- **Branch** — `headRefName`
- **Repo** — da URL da PR
- **Status** — aprovada, changes requested ou pendente

Se merged/closed: **"PR já encerrada. Nada a fazer."**

---

## Etapa 2 — Localizar ou Clonar Repo e Worktree

```bash
find . -maxdepth 2 -type d -name "<nome-do-repo>"
```

Se não encontrado:

```bash
# Tipo de repo determina o diretório:
# Go     → ./go/
# *-infra → ./terraform/
# Node   → ./node/
# Outros → ./

cd <diretorio-destino>
gh repo clone $GITHUB_ORG/<nome-do-repo>
```

Localize ou recrie o worktree:

```bash
cd <caminho-do-repo>
git worktree list
```

Se não existir:

```bash
/worktree create <branch-name>
```

Todas as alterações devem ser feitas dentro do worktree correto.

---

## Etapa 3 — Polling de Comentários e Reviews

**Se `--no-poll` foi passado:** pule esta etapa inteira e vá direto para a Etapa 4. Os comentários já existem e precisam ser resolvidos imediatamente.

**Se modo normal (sem `--no-poll`):** monitore a cada 60s, timeout 24h (`run_in_background: true`, `timeout: 86400000`):

```bash
for i in $(seq 1 1440); do
  REVIEWS=$(gh pr view <PR-URL> --json reviews \
    | jq -r '.reviews[] | select(.state != "COMMENTED") | .state' | tail -1)

  COMMENTS=$(gh pr view <PR-URL> --json comments \
    | jq -r ".comments[] | select(.author.login != \"$SONAR_BOT\") | .body" \
    | tail -5)

  REVIEW_COMMENTS=$(gh api /repos/:owner/:repo/pulls/<PR-NUMBER>/comments \
    | jq -r '.[].body' | tail -5)

  [ "$REVIEWS" = "APPROVED" ] && echo "STATUS:APPROVED" && exit 0

  if [ "$REVIEWS" = "CHANGES_REQUESTED" ] || \
     [ -n "$COMMENTS" ] || [ -n "$REVIEW_COMMENTS" ]; then
    echo "STATUS:HAS_FEEDBACK"
    exit 0
  fi

  echo "⏳ Aguardando revisão... ($((i))min)"
  sleep 60
done
echo "STATUS:TIMEOUT"
```

Se `STATUS:APPROVED` → pule para Etapa 7.
Se `STATUS:HAS_FEEDBACK` → prossiga para Etapa 4.

---

## Etapa 4 — Analisar Comentários e Reviews

### 4.1 — Coletar comentários com IDs

```bash
# Comentários gerais (ignore SONAR_BOT)
gh pr view <PR-URL> --json comments \
  --jq ".comments[] | select(.author.login != \"$SONAR_BOT\") | {id: .id, author: .author.login, body: .body}"

# Review comments inline (por linha de código) — guardar id para reply direto
gh api /repos/$GITHUB_ORG/<repo>/pulls/<PR-NUMBER>/comments \
  | jq '.[] | {id: .id, author: .user.login, file: .path, line: .line, body: .body, node_id: .node_id}'

# Reviews com estado
gh pr view <PR-URL> --json reviews \
  --jq '.reviews[] | {author: .author.login, state: .state, body: .body}'
```

### 4.2 — Coletar threads de review (para resolver após implementar)

```bash
# Buscar threads pendentes via GraphQL — retorna threadId e commentNodeId
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes {
                id
                body
                author { login }
              }
            }
          }
        }
      }
    }
  }
' -f owner="$GITHUB_ORG" -f repo="<repo>" -F pr=<PR-NUMBER> \
  | jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
```

Guarde o mapeamento `comment_node_id → thread_id` para uso na Etapa 5.

### 4.3 — Classificar cada comentário

**CRITICAL:** Comentários de bots de segurança (Aikido, Snyk, Dependabot, CodeQL, etc.) são **sempre bloqueantes** — devem ser tratados como mudança de código, nunca como sugestão opcional. Bots de segurança reportam vulnerabilidades reais que precisam ser corrigidas.

O único bot cujos comentários podem ser ignorados na classificação é o `$SONAR_BOT` (já filtrado na Etapa 4.1), pois o SonarQube é validado separadamente pelo CI.

Classifique cada comentário:

- **Mudança de código** — algo concreto para implementar (inclui TODOS os comentários de bots de segurança)
- **Pergunta/dúvida** — revisor humano quer entender algo
- **Sugestão opcional** — revisor humano sugere melhoria que não bloqueia aprovação
- **Ambíguo** — não está claro o que fazer (apenas de humanos — bots sempre geram ação concreta)

---

## Etapa 5 — Agir sobre Comentários

**CRITICAL:** Toda resposta DEVE ser feita como reply direto no comentário do revisor, NUNCA como comentário geral na PR. Após resolver uma mudança de código, o thread DEVE ser marcado como resolvido.

### Mudança de código:
1. Implemente no worktree seguindo padrões do projeto
2. Execute os testes e corrija falhas antes de prosseguir
3. Commit atômico:
   ```
   fix: <descricao-da-mudança-solicitada>
   ```
4. Responda **diretamente** no comentário do revisor:
   ```bash
   # Para review comments inline (comentários em linha de código)
   gh api /repos/$GITHUB_ORG/<repo>/pulls/<PR-NUMBER>/comments/<COMMENT-ID>/replies \
     -f body="Resolvido em \`<hash>\`. <breve explicação>"
   ```
5. Marque o thread como resolvido:
   ```bash
   gh api graphql -f query='
     mutation($threadId: ID!) {
       resolveReviewThread(input: {threadId: $threadId}) {
         thread { isResolved }
       }
     }
   ' -f threadId="<THREAD-ID>"
   ```

### Pergunta/dúvida:
Responda diretamente no comentário do revisor:
```bash
gh api /repos/$GITHUB_ORG/<repo>/pulls/<PR-NUMBER>/comments/<COMMENT-ID>/replies \
  -f body="<resposta clara e direta>"
```
**Não** marque como resolvido — o revisor decide se a resposta é satisfatória.

### Ambíguo:
Responda diretamente no comentário do revisor:
```bash
gh api /repos/$GITHUB_ORG/<repo>/pulls/<PR-NUMBER>/comments/<COMMENT-ID>/replies \
  -f body="Poderia detalhar melhor o que espera nesse ponto? <dúvida específica>"
```
Notifique no terminal: **"Comentário ambíguo. Aguardando clarificação."**
**Não** marque como resolvido. Volte ao polling da Etapa 3.

### Sugestão opcional:
Avalie se agrega valor sem risco. Se sim, implemente (mesmo fluxo de "Mudança de código" acima, incluindo reply e resolver thread). Se não, responda diretamente no comentário explicando a decisão — **não** marque como resolvido.

---

## Etapa 6 — Push e Novo CI

```bash
git push origin <branch>
```

Aguarde `$SONAR_BOT` (`run_in_background: true`, `timeout: 600000`):

```bash
for i in $(seq 1 10); do
  SONAR=$(gh pr view <PR-URL> --comments --json comments \
    | jq -r "[.comments[] | select(.author.login == \"$SONAR_BOT\")] | last | .body")
  echo "$SONAR" | grep -q "Quality Gate passed" && echo "RESULT:PASSED" && exit 0
  echo "$SONAR" | grep -q "Quality Gate failed" && echo "RESULT:FAILED" && exit 1
  sleep 60
done
echo "RESULT:TIMEOUT"; exit 2
```

Se falhar, corrija e repita (máximo `$CI_MAX_RETRIES` tentativas).

Após CI verde:

1. Se `$SLACK_AUTO_REVIEW` = `true`: notifique os revisores que os comentários foram resolvidos:
   ```
   /slack-review reply <PR-URL>
   ```
   A skill `slack-review` irá responder na thread original mencionando os revisores individualmente.

2. **Se `--no-poll`:** encerre com sucesso — o `/run-queue` gerencia o ciclo de polling externamente. Retorne os dados: task_id, PR-URL, comentários resolvidos, commits de fix.
3. **Se modo normal:** volte ao polling da Etapa 3 para aguardar aprovação.

---

## Etapa 7 — Verificar Aprovação Final

```bash
gh pr view <PR-URL> --json reviews \
  | jq -r '.reviews[] | select(.state == "APPROVED") | .author.login'
```

- **Aprovada** → Etapa 8
- **Pendente** → volta ao polling da Etapa 3
- **Changes requested novamente** → volta à Etapa 4

---

## Etapa 8 — Confirmação Final

```
## ✅ Revisão concluída

- **PR:** <PR-URL>
- **Comentários resolvidos:** <N>
- **Commits de fix:** <N>
- **Revisores que aprovaram:** <lista>
- **Status:** PR aprovada, pronta para /finalize
```

---

## Regras Gerais

- Leia sempre o `CLAUDE.md` — nunca use valores hardcoded.
- Nunca toque no Jira — responsabilidade do `/finalize`.
- Nunca faça merge da PR — responsabilidade do time.
- Commits de resolução sempre com prefixo `fix:`.
- Comentários ambíguos sempre geram pergunta — nunca assuma.
- Sempre rode os testes antes de cada push.
- Máximo `$CI_MAX_RETRIES` tentativas de correção de CI (padrão: 2).
