# Runbook: Hotfix P0

Fluxo acelerado para correções críticas em produção que requerem deploy imediato.

---

## Quando usar

- Bug em produção afetando usuários
- Incidente reportado pelo time de suporte ou monitoramento
- Severidade P0/P1 no Jira

## Diferenças do fluxo padrão

| Etapa | Fluxo padrão | Hotfix P0 |
|-------|-------------|-----------|
| Clareza | Avalia score (threshold) | **Pula** — a urgência justifica suposições |
| Branch | `<TASK-ID>/<descricao>` | `hotfix/<TASK-ID>/<descricao>` |
| DORA commit | Obrigatório | Obrigatório (mantém tracking) |
| Auto-review | Completo (5 critérios) | **Mínimo** — apenas testes passam e sem regressão |
| CI | Aguarda SonarQube | **Fast-track** — apenas testes unitários |
| Review | Aguarda aprovação do time | **Aprovação de 1 reviewer** é suficiente |
| Sandbox | Obrigatório | **Opcional** — pode pular se trivial |
| Homolog | Obrigatório | **Obrigatório** — sempre validar antes de prod |
| Produção | Automático após merge | **Monitorar ativamente** por 15 min após deploy |

## Passo a passo

### 1. Identificar e criar branch

```bash
git checkout main && git pull
git checkout -b hotfix/<TASK-ID>/<descricao-kebab>
git commit -m 'chore: initial commit' --allow-empty
git push -u origin hotfix/<TASK-ID>/<descricao-kebab>
```

### 2. Implementar correção mínima

- Foque APENAS no fix — sem refactoring, sem melhorias
- Menor diff possível
- Adicione teste que reproduz o bug e valida o fix

### 3. Testar localmente

```bash
# Execute apenas os testes relacionados ao fix
go test ./internal/<pacote>/... -run TestNomeDoCaso -v
```

### 4. Abrir PR com label de urgência

```bash
gh pr create \
  --title "<TASK-ID> | Hotfix: <descricao curta>" \
  --body "## Hotfix P0\n\n**Incidente:** <link ou descrição>\n**Causa raiz:** <resumo>\n**Fix:** <o que foi corrigido>\n\n**Validação:** <como testar>" \
  --base main \
  --label "hotfix,ai-first"
```

### 5. Pedir review urgente

Notifique o time diretamente (Slack) — não aguarde polling.

### 6. Deploy

- Homolog é **obrigatório** mesmo em hotfix
- Monitore logs e métricas por 15 min após deploy em produção
- Registre evidência do fix funcionando

### 7. Post-mortem

Após o fix em produção:
- Registre aprendizado via `execution-feedback`
- Avalie se é necessário refactoring posterior (abra task separada)
- Atualize monitoramento/alertas se o cenário não era coberto
