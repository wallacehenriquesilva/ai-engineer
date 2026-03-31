---
name: run
description: >
  Executa o ciclo completo de desenvolvimento de forma autônoma:
  implementa a task, resolve comentários de revisão e finaliza com deploy.
  Invoca engineer → pr-resolve → finalize em sequência.
  Uso: /run
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - TaskCreate
  - TaskUpdate
  - mcp__mcp-atlassian__jira_*
  - mcp__github__*
---

# run: Ciclo Completo Autônomo

Executa o ciclo completo de desenvolvimento sem intervenção manual.
Cada fase depende do sucesso da anterior — se uma falhar, o ciclo encerra.

---

## Fase 1 — Implementação

Invoque a skill `/engineer` e aguarde a conclusão.

O `/engineer` irá:
- Buscar a próxima task disponível
- Avaliar clareza
- Implementar, testar e abrir a PR
- Acionar o CI e aguardar o SonarQube
- Mover a task para `Em Revisão`

Ao final, capture a **PR-URL** retornada pelo `/engineer` no resumo da Etapa 14.

### Se `/engineer` encerrar sem PR aberta:
- Task não encontrada → encerre com: **"Nenhuma task disponível. Ciclo encerrado."**
- Task sem clareza → encerre com: **"Task comentada com perguntas. Ciclo encerrado até ajuste."**
- Falha irrecuperável → encerre com o motivo reportado pelo `/engineer`.

---

## Fase 2 — Revisão

Com a `<PR-URL>` obtida na Fase 1, invoque `/pr-resolve <PR-URL>` e aguarde a conclusão.

O `/pr-resolve` irá:
- Monitorar a PR aguardando comentários ou aprovação do time
- Resolver comentários, responder dúvidas e pedir clareza quando necessário
- Rodar o CI novamente após cada push
- Aguardar aprovação final

### Se `/pr-resolve` encerrar sem aprovação:
- Timeout de 24h sem feedback → encerre com: **"PR sem revisão em 24h. Intervenção manual necessária."**
- Falha de CI irrecuperável → encerre com o motivo reportado.

---

## Fase 3 — Finalização

Com a `<PR-URL>` aprovada, invoque `/finalize <PR-URL>` e aguarde a conclusão.

O `/finalize` irá:
- Validar aprovação
- Fazer deploy em sandbox e homolog
- Gerar evidências de funcionamento
- Atualizar o Jira e fazer o merge
- Acompanhar o deploy em produção

### Se `/finalize` falhar:
- Encerre com o motivo reportado e a orientação de intervenção manual.

---

## Resumo Final

Ao concluir com sucesso todas as fases, exiba:

```
## ✅ Ciclo completo concluído

- **Task:** <KEY> — <summary>
- **PR:** <PR-URL> (merged)
- **Sandbox:** ✅
- **Homolog:** ✅
- **Produção:** ✅
- **Status Jira:** Done

Duração total: <tempo desde o início>
```

---

## Regras

- Nunca pule uma fase — cada uma depende da anterior.
- Preserve o estado entre fases (especialmente a PR-URL).
- Em caso de falha em qualquer fase, encerre com clareza e não tente continuar.
- As skills individuais (/engineer, /pr-resolve, /finalize) continuam disponíveis para execução isolada.
