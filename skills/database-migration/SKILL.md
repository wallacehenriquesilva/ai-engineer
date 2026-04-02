---
name: database-migration
version: 1.0.0
description: >
  Cria e revisa migrations de banco de dados com foco em zero-downtime, seguranca em producao e estrategias de rollback. Aplica o padrao expand-contract, valida operacoes seguras vs perigosas e garante que toda migration tenha plano de reversao testado.
depends-on:
  - sql
triggers:
  - called-by: engineer
  - user-command: /database-migration
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Database Migration

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

Toda migration e um incidente de producao esperando para acontecer — prove que ela e segura.

Este skill guia a criacao e revisao de migrations de banco de dados com foco absoluto em seguranca, zero-downtime e reversibilidade.

## 1. Principios Fundamentais

### 1.1 Zero-Downtime

Nenhuma migration deve causar indisponibilidade do servico. Isso significa:

- **Nunca bloquear tabelas** por periodos longos (locks exclusivos)
- **Apenas operacoes aditivas** em deploys normais — adicionar colunas, tabelas, indices
- **Separar mudancas de schema de mudancas de dados** — schema primeiro, backfill depois
- **Compatibilidade retroativa** — o codigo antigo deve funcionar com o schema novo e vice-versa

### 1.2 Postura Padrao

Antes de executar qualquer migration em producao, responda:

1. Qual o tamanho da tabela afetada? (linhas e bytes)
2. A operacao adquire lock exclusivo? Por quanto tempo?
3. Existe rollback testado?
4. O codigo atual funciona com o schema novo?
5. O codigo novo funciona com o schema antigo?

Se qualquer resposta for "nao sei", a migration **nao esta pronta**.

## 2. Padrao Expand-Contract

O padrao expand-contract e a base para mudancas seguras de schema. Ele divide qualquer alteracao em tres fases:

### Fase 1 — Expand (Expandir)

Adicione a nova estrutura **sem remover a antiga**:

```sql
-- Exemplo: renomear coluna "name" para "full_name"
-- Fase 1: adicionar a nova coluna
ALTER TABLE customers ADD COLUMN full_name VARCHAR(255);
```

Nesta fase, deploy o codigo que **escreve em ambas as colunas** (dual-write).

### Fase 2 — Migrate (Migrar dados)

Preencha a nova coluna com os dados existentes:

```sql
-- Backfill em batches (ver secao 6)
UPDATE customers
SET full_name = name
WHERE full_name IS NULL
  AND id BETWEEN :start AND :end;
```

### Fase 3 — Contract (Contrair)

Somente apos **todos os consumidores** usarem a nova coluna:

```sql
-- Fase 3: remover a coluna antiga (deploy separado, semanas depois)
ALTER TABLE customers DROP COLUMN name;
```

**Regra:** entre a Fase 1 e a Fase 3 devem existir **no minimo 2 deploys separados**. Nunca faca expand e contract na mesma migration.

## 3. Operacoes Seguras vs Perigosas

### 3.1 Operacoes SEGURAS (podem ir para producao diretamente)

| Operacao | Por que e segura | Observacao |
|---|---|---|
| `ADD COLUMN` (nullable) | Nao reescreve a tabela, lock minimo | Padrao preferido |
| `ADD COLUMN ... DEFAULT x` | Instant no PG 11+ (metadado apenas) | Verificar versao do PG |
| `CREATE TABLE` | Tabela nova, sem impacto | — |
| `CREATE INDEX CONCURRENTLY` | Nao bloqueia leituras/escritas | **Obrigatorio** para indices |
| `ADD CONSTRAINT ... NOT VALID` | Nao valida dados existentes | Validar depois com `VALIDATE CONSTRAINT` |
| `DROP INDEX` | Lock minimo | — |

### 3.2 Operacoes PERIGOSAS (requerem expand-contract ou tratamento especial)

| Operacao | Risco | Alternativa segura |
|---|---|---|
| `DROP COLUMN` | Codigo antigo pode referenciar a coluna | Expand-contract: marcar como deprecated, remover apos 2+ deploys |
| `RENAME COLUMN` | Quebra codigo existente imediatamente | Expand-contract: criar nova coluna, dual-write, remover antiga |
| `ALTER TYPE` (ex: varchar para int) | Pode reescrever a tabela inteira, lock exclusivo | Criar nova coluna com tipo correto, migrar, remover antiga |
| `ADD NOT NULL` sem default | Falha se existirem NULLs, lock para validacao | Adicionar nullable + default, backfill NULLs, depois `ADD CONSTRAINT NOT NULL NOT VALID` + `VALIDATE` |
| `ALTER TABLE ... SET NOT NULL` | Lock exclusivo para validacao em tabelas grandes | Usar `ADD CONSTRAINT ... CHECK (col IS NOT NULL) NOT VALID` + `VALIDATE CONSTRAINT` |
| `DROP TABLE` | Perda de dados irreversivel | Renomear para `_deprecated_`, manter por 30 dias, depois dropar |
| `TRUNCATE` | Lock exclusivo, perda de dados | `DELETE` em batches |
| `ALTER TABLE ... ADD PRIMARY KEY` | Reescreve a tabela | Criar indice `CONCURRENTLY` primeiro, depois adicionar constraint usando o indice |

### 3.3 Exemplos Concretos

**ERRADO — migration perigosa:**

```sql
-- Isso bloqueia a tabela inteira durante a criacao do indice
CREATE INDEX idx_orders_customer ON orders(customer_id);

-- Isso falha se existirem NULLs e bloqueia para validar
ALTER TABLE orders ALTER COLUMN status SET NOT NULL;

-- Isso quebra o codigo que referencia a coluna antiga
ALTER TABLE customers RENAME COLUMN name TO full_name;
```

**CORRETO — migration segura:**

```sql
-- Indice sem bloqueio (DEVE estar fora de transacao)
CREATE INDEX CONCURRENTLY idx_orders_customer ON orders(customer_id);

-- NOT NULL via constraint sem bloqueio
ALTER TABLE orders ADD CONSTRAINT orders_status_not_null
  CHECK (status IS NOT NULL) NOT VALID;
-- Em migration separada (pode rodar em horario de baixo trafego):
ALTER TABLE orders VALIDATE CONSTRAINT orders_status_not_null;

-- Rename via expand-contract
ALTER TABLE customers ADD COLUMN full_name VARCHAR(255);
-- (deploy dual-write, backfill, depois dropar 'name' em migration futura)
```

## 4. Arvore de Decisao: "Esta migration e segura para producao?"

Siga este fluxo para cada operacao na migration:

```
A operacao adquire ACCESS EXCLUSIVE lock?
├── NAO → A tabela tem mais de 1M de linhas?
│   ├── NAO → SEGURO (execute normalmente)
│   └── SIM → Testar em homolog com volume real
│       ├── Tempo < 1s → SEGURO
│       └── Tempo >= 1s → Usar batches ou expand-contract
└── SIM → E possivel usar alternativa sem lock exclusivo?
    ├── SIM → Reescrever usando alternativa segura (ver tabela 3.1)
    └── NAO → A tabela tem mais de 100k linhas?
        ├── NAO → SEGURO (lock sera breve)
        └── SIM → PERIGOSO
            ├── Usar pg_repack para ALTER TYPE
            ├── Usar expand-contract para RENAME/DROP
            └── Agendar janela de manutencao se inevitavel
```

**Regra de ouro:** se voce precisa perguntar se e seguro, provavelmente nao e. Use expand-contract.

## 5. Estrategia de Rollback

**Toda migration DEVE ter um plano de rollback documentado.**

### 5.1 Regras de Rollback

1. **Migrations aditivas** (ADD COLUMN, CREATE TABLE): rollback e simplesmente dropar o que foi adicionado
2. **Migrations destrutivas** (DROP, ALTER TYPE): rollback e impossivel sem backup — **por isso usamos expand-contract**
3. **Migrations de dados** (UPDATE, INSERT): rollback requer backup dos dados originais ou coluna de versionamento

### 5.2 Formato do Arquivo de Rollback

Para cada arquivo `XXXXXX_descricao.up.sql`, crie `XXXXXX_descricao.down.sql`:

```sql
-- 20260331120000_add_full_name_to_customers.up.sql
ALTER TABLE customers ADD COLUMN full_name VARCHAR(255);

-- 20260331120000_add_full_name_to_customers.down.sql
ALTER TABLE customers DROP COLUMN IF EXISTS full_name;
```

### 5.3 Validacao de Rollback

Antes de aprovar uma migration, execute o ciclo completo:

```bash
# Aplicar migration
migrate up

# Verificar schema
psql -c "\d+ tabela_afetada"

# Reverter migration
migrate down

# Verificar que schema voltou ao original
psql -c "\d+ tabela_afetada"

# Aplicar novamente (idempotencia)
migrate up
```

Se o ciclo `up → down → up` falhar, a migration **nao esta pronta**.

## 6. Backfill de Dados

### 6.1 Regra Principal

**Nunca misture mudancas de schema com backfill na mesma migration.**

- Migration 1: `ALTER TABLE ADD COLUMN ...`
- Migration 2 (ou script separado): `UPDATE ... SET coluna = valor`

### 6.2 Processamento em Batches

Para tabelas com mais de 100k linhas, sempre use batches:

```sql
-- Errado: atualiza tudo de uma vez (lock longo, possivel OOM)
UPDATE orders SET new_status = old_status;

-- Correto: batches de 10k com pausa
DO $$
DECLARE
  batch_size INT := 10000;
  affected INT := 1;
  total_updated INT := 0;
BEGIN
  WHILE affected > 0 LOOP
    UPDATE orders
    SET new_status = old_status
    WHERE new_status IS NULL
      AND id IN (
        SELECT id FROM orders
        WHERE new_status IS NULL
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
      );
    GET DIAGNOSTICS affected = ROW_COUNT;
    total_updated := total_updated + affected;
    RAISE NOTICE 'Atualizados: % (total: %)', affected, total_updated;
    COMMIT;
    PERFORM pg_sleep(0.1); -- pausa entre batches
  END LOOP;
END $$;
```

### 6.3 Acompanhamento de Progresso

Para backfills longos, mantenha visibilidade:

```sql
-- Antes de iniciar, verificar volume total
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE new_column IS NULL) AS pendentes
FROM tabela;

-- Durante a execucao, monitorar progresso
SELECT
  COUNT(*) FILTER (WHERE new_column IS NOT NULL) AS migrados,
  COUNT(*) FILTER (WHERE new_column IS NULL) AS pendentes,
  ROUND(100.0 * COUNT(*) FILTER (WHERE new_column IS NOT NULL) / COUNT(*), 2) AS pct_completo
FROM tabela;
```

## 7. Migrations em Tabelas Grandes (milhoes de linhas)

### 7.1 Identificar Tabelas Grandes

```sql
SELECT schemaname, relname, n_live_tup,
       pg_size_pretty(pg_total_relation_size(relid)) AS tamanho_total
FROM pg_stat_user_tables
WHERE n_live_tup > 1000000
ORDER BY n_live_tup DESC;
```

### 7.2 Estrategias para Tabelas Grandes

1. **CREATE INDEX CONCURRENTLY** — obrigatorio, nunca usar `CREATE INDEX` simples
2. **Batched updates** — nunca atualizar todas as linhas de uma vez
3. **pt-online-schema-change / pg_repack** — para ALTER TYPE ou mudancas que requerem reescrita
4. **Shadow table** — para alteracoes complexas:
   - Criar tabela nova com schema desejado
   - Copiar dados em batches
   - Usar trigger para capturar mudancas durante a copia
   - Renomear tabelas atomicamente

### 7.3 pg_repack

Usado para reorganizar tabelas sem lock exclusivo prolongado:

```bash
# Reorganizar tabela com bloat
pg_repack --table=orders --jobs=2 --wait-timeout=60

# Reorganizar e mudar tipo de coluna simultaneamente
# (requer criacao de coluna nova primeiro)
```

### 7.4 Advisory Locks para Migration Runners

Garanta que apenas um runner execute migrations simultaneamente:

```sql
-- No inicio da migration
SELECT pg_advisory_lock(12345);

-- Executar migrations...

-- No final
SELECT pg_advisory_unlock(12345);
```

Ferramentas como golang-migrate ja fazem isso automaticamente. Verifique a configuracao do seu runner.

## 8. Especifidades do PostgreSQL

### 8.1 ADD COLUMN com DEFAULT (PG 11+)

A partir do PostgreSQL 11, `ADD COLUMN ... DEFAULT` e uma operacao instantanea (metadado apenas):

```sql
-- Instantaneo no PG 11+, nao reescreve a tabela
ALTER TABLE orders ADD COLUMN priority INTEGER DEFAULT 0;
```

**Atencao:** em versoes anteriores ao PG 11, essa operacao reescreve a tabela inteira.

### 8.2 CREATE INDEX CONCURRENTLY

```sql
-- OBRIGATORIO: sempre usar CONCURRENTLY para indices em producao
-- ATENCAO: nao pode rodar dentro de uma transacao
CREATE INDEX CONCURRENTLY idx_orders_created_at ON orders(created_at);
```

Se o indice falhar no meio da criacao, ele fica em estado `INVALID`. Limpe com:

```sql
-- Verificar indices invalidos
SELECT indexrelid::regclass, indisvalid
FROM pg_index
WHERE NOT indisvalid;

-- Dropar e recriar
DROP INDEX CONCURRENTLY idx_orders_created_at;
CREATE INDEX CONCURRENTLY idx_orders_created_at ON orders(created_at);
```

### 8.3 VALIDATE CONSTRAINT (em separado)

```sql
-- Migration 1: adicionar constraint sem validar (instantaneo)
ALTER TABLE orders
ADD CONSTRAINT chk_status_not_null CHECK (status IS NOT NULL) NOT VALID;

-- Migration 2: validar constraint (scan da tabela, mas sem lock exclusivo)
ALTER TABLE orders VALIDATE CONSTRAINT chk_status_not_null;
```

### 8.4 Monitoramento de Locks

Antes de executar migrations em producao, monitore locks ativos:

```sql
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_query,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

## 9. Ferramentas de Migration

### 9.1 golang-migrate (Go)

Padrao para servicos Go na Conta Azul:

```
migrations/
  000001_create_users.up.sql
  000001_create_users.down.sql
  000002_add_email_to_users.up.sql
  000002_add_email_to_users.down.sql
```

```bash
# Aplicar todas as migrations pendentes
migrate -path migrations -database "$DATABASE_URL" up

# Reverter ultima migration
migrate -path migrations -database "$DATABASE_URL" down 1

# Verificar versao atual
migrate -path migrations -database "$DATABASE_URL" version
```

### 9.2 Flyway (Java)

Padrao para servicos Java/Spring Boot:

```
src/main/resources/db/migration/
  V1__create_users.sql
  V2__add_email_to_users.sql
  R1__refresh_materialized_view.sql  (repeatable)
```

### 9.3 Alembic (Python)

Padrao para servicos Python:

```bash
alembic revision --autogenerate -m "add email to users"
alembic upgrade head
alembic downgrade -1
```

### 9.4 Knex (Node.js)

Padrao para servicos Node/TypeScript:

```bash
knex migrate:make add_email_to_users
knex migrate:latest
knex migrate:rollback
```

## 10. Convencoes de Nomenclatura

### 10.1 Formato do Arquivo

```
<timestamp>_<descricao_em_snake_case>.<up|down>.sql
```

Exemplos:
- `20260331120000_create_customers_table.up.sql`
- `20260331120000_create_customers_table.down.sql`
- `20260331130000_add_email_index_to_customers.up.sql`
- `20260331130000_add_email_index_to_customers.down.sql`

### 10.2 Regras de Nome

- Use **timestamp** como prefixo (formato `YYYYMMDDHHmmss`), nunca numeros sequenciais
- Descricao deve indicar **o que a migration faz**, nao o ticket
- Use verbos: `create_`, `add_`, `remove_`, `alter_`, `drop_`, `backfill_`
- Snake_case sempre
- Nunca abreviar nomes de tabelas ou colunas no nome do arquivo

### 10.3 Exemplos de Bons Nomes

```
20260331120000_create_orders_table.up.sql
20260331130000_add_customer_id_to_orders.up.sql
20260331140000_create_index_orders_customer_id.up.sql
20260331150000_backfill_orders_status_default.up.sql
20260331160000_add_not_null_constraint_orders_status.up.sql
20260331170000_drop_deprecated_column_orders_legacy_status.up.sql
```

## 11. Ambientes e Ordem de Execucao

### 11.1 Pipeline de Ambientes

As **mesmas migrations** devem rodar em todos os ambientes, na mesma ordem:

```
sandbox → homolog → producao
```

- **Sandbox:** validacao inicial, pode falhar e ser recriado
- **Homolog:** validacao com volume proximo ao real, deve simular producao
- **Producao:** execucao final, monitorada, com plano de rollback pronto

### 11.2 Timing

- Sandbox: migration roda no deploy (automatico)
- Homolog: migration roda no deploy (automatico), validar impacto
- Producao: migration roda no deploy, **monitorar metricas** (latencia, erros, locks)

### 11.3 Nunca Faca

- Migrations que so funcionam em um ambiente (ex: dados hardcoded de sandbox)
- Migrations condicionais por ambiente (`IF env = 'production'`)
- Pular ambientes — sempre sandbox → homolog → producao

## 12. Dependencias e Ordenacao

### 12.1 Regras de Dependencia

- Cada migration deve ser **autocontida** — nao depender de estado do codigo
- Se migration B depende de migration A, B deve ter timestamp **posterior**
- Nunca reordenar migrations ja aplicadas em producao
- Nunca editar migrations ja aplicadas — crie uma nova migration corretiva

### 12.2 Migrations entre Servicos

Se dois servicos compartilham banco (legado):

1. Definir **um unico owner** da migration
2. Coordenar a ordem de deploy
3. Preferir: separar os bancos (cada servico com seu banco)

## 13. Testando Migrations

### 13.1 Testes Obrigatorios

Antes de aprovar qualquer migration:

```bash
# 1. Aplicar migration
migrate up

# 2. Verificar schema resultante
psql -c "\d+ tabela"

# 3. Reverter migration
migrate down 1

# 4. Verificar que voltou ao estado original
psql -c "\d+ tabela"

# 5. Aplicar novamente (idempotencia)
migrate up

# 6. Verificar integridade dos dados (se backfill)
psql -c "SELECT COUNT(*) FROM tabela WHERE coluna IS NULL"
```

### 13.2 Testes com Volume

Para tabelas grandes, testar em homolog com volume realista:

```bash
# Medir tempo de execucao
\timing on
-- executar migration

# Verificar locks durante execucao (em outra sessao)
SELECT * FROM pg_stat_activity WHERE state = 'active' AND wait_event_type = 'Lock';
```

## 14. Procedimentos de Emergencia

### 14.1 Migration Falhou em Producao

1. **NAO entre em panico.** Avalie o estado atual:
   ```sql
   -- Verificar versao atual da migration
   SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 5;

   -- Verificar se ha transacoes abertas
   SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction';
   ```

2. **Se a migration esta parcialmente aplicada:**
   - Verifique o que foi executado e o que faltou
   - Execute o rollback (down) se disponivel e seguro
   - Se nao houver rollback, corrija manualmente e registre a versao

3. **Se ha lock bloqueando queries:**
   ```sql
   -- Identificar o PID que esta bloqueando
   SELECT pid, query, state, wait_event
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY query_start;

   -- Cancelar a query (graceful)
   SELECT pg_cancel_backend(<pid>);

   -- Se nao funcionar, terminar o processo (forcado)
   SELECT pg_terminate_backend(<pid>);
   ```

4. **Comunicar o time** — qualquer intervencao manual em producao deve ser documentada

### 14.2 Estado Dirty da Migration

Se o runner marcou a migration como "dirty":

```bash
# golang-migrate: forcar a versao para a ultima aplicada com sucesso
migrate -path migrations -database "$DATABASE_URL" force <versao_correta>
```

### 14.3 Checklist Pos-Incidente

- [ ] Schema esta consistente?
- [ ] Dados estao integros?
- [ ] Aplicacao esta funcionando?
- [ ] Migration corretiva foi criada?
- [ ] Rollback foi documentado?
- [ ] Post-mortem foi agendado?

## 15. Checklist de Revisao de Migration

Ao revisar uma PR com migration, valide cada item:

- [ ] Tem arquivo de rollback (down)?
- [ ] O ciclo up → down → up funciona?
- [ ] Operacoes perigosas estao usando expand-contract?
- [ ] Indices usam `CONCURRENTLY`?
- [ ] Backfill esta separado da alteracao de schema?
- [ ] Backfill usa batches (se tabela > 100k linhas)?
- [ ] Nome do arquivo segue a convencao de timestamp?
- [ ] Descricao do arquivo e clara sobre o que faz?
- [ ] Nao ha dados hardcoded de ambiente?
- [ ] Foi testada em homolog com volume proximo ao real?
- [ ] Plano de rollback esta documentado na PR?
