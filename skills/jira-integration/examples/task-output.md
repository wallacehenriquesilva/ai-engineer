## Task: PROJ-1234 — Expandir endpoint com novos campos

**Status:** Fazendo
**Prioridade:** High
**Assignee:** dev.user

### Descricao
**Contexto:**

O endpoint PATCH /v1/resources/{id}/attributes precisa aceitar novos campos opcionais. O frontend evoluiu para exibir um formulario com multiplas perguntas, e o endpoint precisa acompanhar essa evolucao.

**O que fazer:**

Adicionar 4 novos campos opcionais ao endpoint existente, criando os enums correspondentes, adicionando na entity, criando a migration de banco e garantindo a propagacao via eventos.

**Repositorio:** https://github.com/your-org/your-api

**Endpoints impactados:**

| Metodo | Endpoint | Mudanca |
|--------|----------|---------|
| PATCH | /v1/resources/{id}/attributes | Aceitar 4 novos campos opcionais |
| GET | /v1/resources/{id} | Retornar os novos campos na response |

**Criterios de aceite:**
- O endpoint aceita cada campo individualmente (todos omitempty)
- O endpoint rejeita valores invalidos (retorna 400)
- Testes unitarios e de integracao cobrindo os novos campos
- Nenhum endpoint existente quebra (backward compatible)

### Subtasks
- PROJ-1235 — Criar enums — To Do
- PROJ-1236 — Adicionar campos no model — To Do
- PROJ-1237 — Criar migration de banco — To Do

### Links
- PROJ-1230 (is blocked by) — Done
- PROJ-1240 (relates to) — To Do

### Labels
AI, backend
