---
triggers:
  labels: [refactoring, tech-debt]
  estimated_files: 10+
  keywords: [migração, renomear, refatorar, mover pacote, trocar interface]
---

# Runbook: Refactoring Grande

Fluxo para refactorings que afetam múltiplos arquivos/pacotes e requerem estratégia de PRs.

---

## Quando usar

- Refactoring afeta 10+ arquivos ou 3+ pacotes
- Mudança de interface/contrato que impacta consumers
- Migração de padrão (ex: middleware antigo → novo)
- Renomeação em larga escala

## Estratégia: Multi-PR incremental

**Nunca** faça um refactoring grande em uma única PR. Divida em PRs incrementais que podem ser mergeadas independentemente.

### Ordem recomendada de PRs

```
PR 1: Preparação (sem mudança de comportamento)
  └── Adiciona novas interfaces/structs
  └── Adiciona adaptadores de compatibilidade
  └── Testes para a nova interface

PR 2-N: Migração gradual (uma área por PR)
  └── Migra um pacote/consumer por PR
  └── Testes passam antes e depois
  └── Código antigo e novo coexistem

PR Final: Limpeza
  └── Remove código antigo
  └── Remove adaptadores de compatibilidade
  └── Atualiza documentação
```

## Passo a passo

### 1. Planejar a decomposição

Antes de implementar, crie um plano em `.claude/plans/plan-<TASK-ID>.md` com:

- Lista de todos os arquivos afetados
- Agrupamento por PR (critério: cada PR deve compilar e testes devem passar)
- Ordem de execução (dependências entre PRs)
- Pontos de rollback (até onde pode reverter sem quebrar)

### 2. Branch strategy

Cada PR usa sua própria branch:

```
<TASK-ID>/refactor-01-add-new-interface
<TASK-ID>/refactor-02-migrate-consumer-x
<TASK-ID>/refactor-03-migrate-consumer-y
<TASK-ID>/refactor-final-cleanup
```

### 3. Para cada PR

1. Implemente apenas o escopo daquela PR
2. Garanta que testes passam em isolamento
3. Garanta compatibilidade reversa (código antigo e novo coexistem)
4. Abra PR com contexto da estratégia geral:
   ```
   PR 2/4 do refactoring <TASK-ID>: migra consumer X para nova interface.
   PRs relacionadas: #<pr1>, #<pr3>, #<pr4>
   ```

### 4. Regras de segurança

- **Cada PR deve ser mergeável independentemente**
- **Nunca quebre backward compatibility** em PRs intermediárias
- **Se uma PR intermediária for rejeitada**, ajuste sem afetar as posteriores
- **Feature flags** são aceitáveis se a coexistência for complexa
- **Testes de integração** devem passar com qualquer combinação de PRs mergeadas

### 5. Monitoramento pós-merge

- Monitore métricas de performance após cada PR mergeada
- Se houver degradação, pause e investigue antes da próxima PR
