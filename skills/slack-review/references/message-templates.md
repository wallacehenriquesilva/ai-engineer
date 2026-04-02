# Templates de Mensagem

Templates padrão para mensagens no Slack. O usuário pode sobrescrever estes templates
adicionando uma seção `## Slack Review Templates` no `CLAUDE.md` do repositório.

## Template: Request

```
:code-review: Code Review
Envolvidos: <REVIEWERS>
Descrição: <RESUMO>
Link to PR: <PR-URL>

Ao revisar:

Se aprovar marque :white_check_mark:
Se Comentar: :speech_balloon:
Se bloquear: :no_entry_sign:
Se tiver comentários adicionais comente na thread.
```

### Campos disponíveis para customização

O usuário pode usar estes placeholders no template do CLAUDE.md:

| Placeholder | Descrição |
|---|---|
| `<@USER_ID_AUTOR>` | Menção do autor da PR |
| `<PR-URL>` | Link da PR |
| `<TITULO>` | Título da PR |
| `<DESCRICAO>` | Descrição/body da PR (resumida) |
| `<RESUMO>` | Breve resumo em PT-BR do que foi feito na PR, gerado pelo agente para auxiliar os revisores |
| `<ARQUIVOS>` | Lista de arquivos alterados |
| `<REVIEWERS>` | Menções dos reviewers solicitados |

### Exemplo de customização no CLAUDE.md

```markdown
## Slack Review Templates
### Request
:code-review: Code Review
Solicitado por: <@USER_ID_AUTOR>
Descrição: <TITULO>
Link to PR: <PR-URL>
Reviewers: <REVIEWERS>
Arquivos: <ARQUIVOS>
```

## Template: Reply

```
<@USER_ID_REVISOR> Comentários revisados e implementados! :white_check_mark:

Resumo das alterações:
- <breve descrição do que foi feito para cada comentário>

Os commits com as correções já estão na PR.
```

### Indicadores de status

Adicione automaticamente ao final da resposta:

| Status da PR | Indicador |
|---|---|
| Merged | :merged: |
| Aprovada | :white_check_mark: |
| Changes requested | :warning: (ainda pendente) |
