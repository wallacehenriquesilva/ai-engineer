---
name: jira-task-clarity
description: >
  Avalia o grau de clareza e confiança de uma task do Jira antes da implementação.
  Acione esta skill quando quiser saber se uma task está clara o suficiente para ser implementada,
  ou quando o agente precisar decidir se pode prosseguir com segurança.
  Analisa descrição, critérios de aceitação, escopo, contexto técnico, ambiguidades e dependências.
  Quando a task não estiver clara o suficiente, formula perguntas objetivas e as posta como comentário no Jira.
context: default
allowed-tools:
  - mcp__mcp-atlassian__jira_get_issue
---

# Jira Task Clarity

Avalia se uma task tem informações suficientes para ser implementada com segurança, e age conforme o resultado.

## 1. Obter dados da task

Se a chave da task não foi fornecida, use a task mais recente do contexto da conversa.

Use `jira-integration` com os campos: `summary`, `description`, `customfield_13749`, `labels`, `issuelinks`, `subtasks`, `status`, `priority`, `assignee`.

Para a descrição: use `description` se preenchido; caso contrário, use `customfield_13749`; se ambos preenchidos, combine os dois.

---

## 2. Avaliar as dimensões

Analise a task nas seguintes dimensões. Para cada uma, atribua uma nota de 1 a 3:

- **1 — Insuficiente:** informação ausente ou muito vaga
- **2 — Parcial:** informação presente mas com lacunas ou ambiguidades
- **3 — Suficiente:** claro o bastante para implementar sem suposições

| Dimensão | Nota 3 (Suficiente) | Nota 2 (Parcial) | Nota 1 (Insuficiente) |
|---|---|---|---|
| **Contexto de negócio** | Explica o porquê: problema, motivação, como se encaixa no sistema | Contexto vago ou incompleto | Ausente — não dá para entender o propósito |
| **O que fazer** | Descreve claramente o que deve ser construído/alterado, sem ambiguidade | Descreve parcialmente, com lacunas interpretáveis | Vago ou genérico demais |
| **Repositórios e serviços** | Aponta os repos, serviços e tópicos/filas envolvidos com links | Menciona sem links ou incompleto | Não menciona onde o trabalho deve ser feito |
| **Como fazer** | Passo a passo técnico com endpoints, campos, regras de validação e exemplos de código | Direção geral sem detalhes suficientes | Ausente — o agente teria que inferir tudo |
| **Critérios de aceitação** | Lista explícita e verificável do que define "feito" (ex: cobertura mínima, ambientes, logs) | Critérios vagos ou parciais | Ausente — não dá para saber quando está correto |
| **Links e referências** | Aponta docs, Notion, Confluence, exemplos ou discoveries relevantes | Referências mencionadas mas sem links | Ausente ou links quebrados |

---

## 3. Calcular resultado geral

Some as notas e classifique:

- **15–18 pontos → ✅ Pronto:** implementar diretamente
- **10–14 pontos → ⚠️ Implementar com ressalvas:** prosseguir documentando as suposições feitas
- **6–9 pontos → ❌ Requer clarificação:** risco alto de retrabalho, formular perguntas e comentar na task

---

## 4. Agir conforme o resultado

Apresente sempre o relatório da Seção 5 e sinalize o resultado claramente para que o agente que invocou esta skill possa decidir o próximo passo:

- **✅ Pronto** — task clara, pode prosseguir com a implementação
- **⚠️ Implementar com ressalvas** — liste as suposições que precisariam ser adotadas
- **❌ Requer clarificação** — liste as perguntas objetivas que precisam ser respondidas antes de prosseguir

---

## 5. Formato do relatório

```
## Análise de Clareza — <issueKey>: <summary>

**Resultado:** <✅ Pronto | ⚠️ Implementar com ressalvas | ❌ Requer clarificação>
**Pontuação:** <total>/18

| Dimensão               | Nota | Observação                          |
|------------------------|------|-------------------------------------|
| Clareza da descrição   | <n>  | <motivo breve>                      |
| Critérios de aceitação | <n>  | <motivo breve>                      |
| Escopo                 | <n>  | <motivo breve>                      |
| Contexto técnico       | <n>  | <motivo breve>                      |
| Ambiguidades           | <n>  | <motivo breve>                      |
| Dependências externas  | <n>  | <motivo breve>                      |

### Suposições adotadas
<Liste apenas se resultado for ⚠️. Caso contrário, omita esta seção.>

### Perguntas para clarificação
<Liste as perguntas caso resultado for ❌. Caso contrário, omita esta seção.>
```

---

## Regras

- Nunca pule a avaliação mesmo que a task pareça simples à primeira vista.
- Nunca invente informações ausentes — se não está na task, é lacuna.
- Esta skill não implementa código, não move tasks e não posta comentários — apenas avalia e retorna o relatório.