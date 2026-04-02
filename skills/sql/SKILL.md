---
name: sql
version: 1.1.0
description: >
  Skill especializada em escrita, revisao e otimizacao de codigo SQL. Cobre prevencao de SQL injection, otimizacao de queries, estrategia de indices, transacoes, migracao segura de schema e padroes especificos por banco de dados. Postura padrao: toda query e um problema de performance em potencial ate que se prove o contrario.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /sql
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# SQL: Escrita, Revisao e Otimizacao de Codigo de Banco de Dados

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

Postura padrao: **toda query e um problema de performance em potencial ate que se prove o contrario.**

Ao escrever ou revisar codigo SQL, siga rigorosamente todas as secoes abaixo.

---

## Deteccao Automatica do Banco de Dados

Antes de aplicar padroes especificos, detecte o banco pelo codigo do projeto:

| Driver / Dependencia | Banco de Dados |
|---|---|
| `database/sql` com `lib/pq` ou `pgx` (Go) | PostgreSQL |
| `HikariCP` + `postgresql` driver (Java) | PostgreSQL |
| `SQLAlchemy` + `psycopg2` ou `asyncpg` (Python) | PostgreSQL |
| `Prisma` com `provider = "postgresql"` (JS/TS) | PostgreSQL |
| `mysql` driver, `go-sql-driver/mysql` | MySQL |
| `SQLAlchemy` + `pymysql` ou `mysqlclient` | MySQL |
| `mssql`, `go-mssqldb` | SQL Server |
| `godror`, `cx_Oracle` | Oracle |

Apos detectar o banco, consulte a referencia especifica para padroes e otimizacoes adicionais.

---

## Referencias por Banco de Dados

Consulte a referencia do banco utilizado no projeto para padroes especificos:

- [PostgreSQL](references/postgresql.md) — CTEs, window functions, JSONB, array types, indices parciais, CREATE INDEX CONCURRENTLY, pg_repack, advisory locks, tipos de dados, niveis de isolamento e anti-patterns especificos.

> **Nota:** a maioria dos projetos Conta Azul usa PostgreSQL. Quando nao houver referencia especifica para o banco detectado, aplique os padroes genericos desta skill.

---

## 1. Prevencao de SQL Injection

SQL injection e a vulnerabilidade mais critica em codigo de banco de dados. Tolerancia zero.

### Regras absolutas

- **SEMPRE** use queries parametrizadas (prepared statements). Sem excecao.
- **NUNCA** concatene strings para montar queries. Nem para clausulas `ORDER BY`, `LIMIT` ou nomes de tabela.
- **NUNCA** use `fmt.Sprintf`, `f-strings`, template literals ou qualquer interpolacao de string em queries SQL.
- Prefira ORMs ou query builders que parametrizem automaticamente (GORM, sqlx, SQLAlchemy, Prisma).

### Exemplo correto (Go com sqlx)

```go
// BOM: parametrizado
err := db.Get(&user, "SELECT id, name FROM users WHERE email = $1", email)
```

### Exemplo ERRADO

```go
// PROIBIDO: concatenacao direta
query := fmt.Sprintf("SELECT id, name FROM users WHERE email = '%s'", email)
err := db.Get(&user, query)
```

### Para clausulas dinamicas (ORDER BY, filtros opcionais)

- Use allowlists (mapas de valores permitidos) para nomes de colunas e direcoes.
- Construa a query com query builders, nunca com concatenacao.

```go
// Allowlist para ORDER BY
allowedColumns := map[string]bool{"name": true, "created_at": true, "email": true}
if !allowedColumns[sortColumn] {
    sortColumn = "created_at" // fallback seguro
}
```

---

## 2. Otimizacao de Queries

### EXPLAIN ANALYZE e obrigatorio

Antes de aprovar qualquer query que opere em tabelas com mais de 10k linhas, exija `EXPLAIN ANALYZE`:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT u.id, u.name, o.total
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.created_at > '2025-01-01';
```

Pontos de atencao no plano de execucao:
- **Seq Scan** em tabelas grandes = sinal de alerta (indice ausente ou nao utilizado).
- **Nested Loop** com tabela interna grande = possivel N+1 no banco.
- **Sort** sem indice = custo desnecessario.
- **Hash Join** com `Rows Removed by Filter` alto = filtro ineficiente.

### Evite SELECT *

- Liste explicitamente as colunas necessarias.
- `SELECT *` impede covering indexes, transfere dados desnecessarios e quebra com alteracoes de schema.

```sql
-- RUIM
SELECT * FROM orders WHERE user_id = 42;

-- BOM
SELECT id, total, status, created_at FROM orders WHERE user_id = 42;
```

### Problema N+1

O N+1 e o assassino silencioso de performance. Ocorre quando o codigo faz 1 query para buscar uma lista e depois N queries adicionais (uma por item).

```go
// RUIM: N+1
users, _ := db.Query("SELECT id, name FROM users LIMIT 100")
for users.Next() {
    // Uma query por usuario!
    db.Query("SELECT count(*) FROM orders WHERE user_id = $1", user.ID)
}

// BOM: JOIN ou subquery
db.Query(`
    SELECT u.id, u.name, COUNT(o.id) as order_count
    FROM users u
    LEFT JOIN orders o ON o.user_id = u.id
    GROUP BY u.id, u.name
    LIMIT 100
`)
```

### Paginacao

- **NUNCA** use `OFFSET` para paginacao profunda. O custo cresce linearmente.
- Use **keyset pagination** (cursor-based):

```sql
-- RUIM: offset em pagina 1000
SELECT id, name FROM users ORDER BY id LIMIT 20 OFFSET 20000;

-- BOM: keyset pagination
SELECT id, name FROM users WHERE id > $1 ORDER BY id LIMIT 20;
```

---

## 3. Estrategia de Indices

### Quando criar indices

- Toda coluna usada em `WHERE`, `JOIN ON`, `ORDER BY` ou `GROUP BY` frequentemente deve ter indice.
- Verifique se o banco cria indices automaticamente em foreign keys (PostgreSQL NAO cria; MySQL InnoDB cria).
- Colunas com alta seletividade (muitos valores distintos) se beneficiam mais de indices.

### Tipos de indices

**Indice composto (multi-coluna):**
- A ordem das colunas importa. Coloque a coluna mais seletiva primeiro.
- O indice `(a, b, c)` atende queries com `WHERE a = ?`, `WHERE a = ? AND b = ?`, mas NAO atende `WHERE b = ?` sozinho.

```sql
-- Para queries que filtram por tenant_id e status
CREATE INDEX idx_orders_tenant_status ON orders (tenant_id, status);
```

### Quando NAO criar indices

- Tabelas pequenas (< 1000 linhas): seq scan e mais rapido.
- Colunas com baixissima seletividade (ex: booleano em tabela de 10M linhas).
- Tabelas com altissima taxa de escrita e baixa taxa de leitura (cada indice pesa no INSERT/UPDATE).

> **Nota:** para tipos de indices especificos (covering index, indices parciais, GIN, trigram), consulte a referencia do banco em uso.

---

## 4. Transacoes

### Prevencao de deadlocks

- **SEMPRE** adquira locks na mesma ordem em todas as transacoes.
- Acesse tabelas na mesma sequencia (ex: sempre `users` antes de `orders`).
- Mantenha transacoes curtas. Nada de chamadas HTTP ou processamento pesado dentro de uma transacao.
- Use timeouts: `SET lock_timeout = '5s';`

### Optimistic locking

Prefira optimistic locking em vez de `SELECT ... FOR UPDATE` quando a contencao e baixa:

```sql
-- Leitura com versao
SELECT id, name, balance, version FROM accounts WHERE id = $1;

-- Update com check de versao
UPDATE accounts
SET balance = balance - $1, version = version + 1
WHERE id = $2 AND version = $3;
-- Se rows affected = 0, houve conflito. Retente.
```

### Regras de transacao

- Transacoes devem ser atomicas e curtas.
- NUNCA deixe uma transacao aberta esperando input do usuario ou resposta de API externa.
- Use `SAVEPOINT` para rollback parcial quando necessario.
- Sempre trate erros e faca `ROLLBACK` explicito em caso de falha.

> **Nota:** para niveis de isolamento especificos do banco (Read Committed, Repeatable Read, Serializable), consulte a referencia do banco em uso.

---

## 5. Connection Pooling

### Regras

- **SEMPRE** use um connection pool.
- Configure limites adequados: `max_connections` do pool deve ser **menor** que `max_connections` do banco.
- Em microservicos, cada instancia deve ter pool pequeno (5-20 conexoes). A soma de todos os pools nao deve exceder o limite do banco.

### Configuracoes essenciais

```yaml
# Exemplo para HikariCP / Spring Boot
spring:
  datasource:
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 5000    # 5s para obter conexao
      idle-timeout: 300000        # 5min para conexao ociosa
      max-lifetime: 600000        # 10min vida maxima da conexao
      leak-detection-threshold: 30000  # alerta se conexao nao retorna em 30s
```

### Armadilhas

- Nunca abra e feche conexoes manualmente em cada request. Use o pool.
- Conexoes vazadas (nao devolvidas ao pool) sao a causa #1 de esgotamento. Configure `leak-detection`.

> **Nota:** para configuracoes especificas de pooling por banco (PgBouncer, pgxpool, etc.), consulte a referencia do banco em uso.

---

## 6. Design de Schema

### Normalizacao vs Denormalizacao

**Normalizacao (3NF) como padrao:**
- Elimina redundancia, garante consistencia, facilita manutencao.
- Use para dados transacionais (pedidos, usuarios, pagamentos).

**Denormalizacao quando justificada:**
- Queries de leitura com muitos JOINs que impactam performance comprovadamente.
- Dados de analytics/reporting que sao consumidos como snapshots.
- Cache materializado (materialized views, tabelas de projecao).
- **Sempre documente** por que a denormalizacao existe e como manter a consistencia.

### Regra pratica

> Normalize primeiro, denormalize depois — e apenas com dados de EXPLAIN ANALYZE que justifiquem.

---

## 7. Tipos de Dados

### Escolhas corretas (independentes de banco)

| Situacao | Use | Evite |
|---|---|---|
| Texto com limite real de negocio | `VARCHAR(N)` com N significativo | `CHAR(N)` (padding desperdicado) |
| Apenas data | `DATE` | `TIMESTAMP` para so guardar data |
| Identificadores distribuidos | `UUID` | Auto-incremento em sistemas distribuidos |
| Dinheiro/valores monetarios | `NUMERIC(precision, scale)` ou `DECIMAL` | `FLOAT`, `DOUBLE`, `MONEY` (imprecisao) |
| Booleano | `BOOLEAN` | `INTEGER` 0/1 ou `CHAR(1)` S/N |

> **Nota:** para tipos de dados especificos do banco (JSONB, TEXT vs VARCHAR, TIMESTAMPTZ, IDENTITY, etc.), consulte a referencia do banco em uso.

---

## 8. Constraints

### Postura: use constraints agressivamente

Constraints sao a ultima linha de defesa dos seus dados. O banco deve rejeitar dados invalidos mesmo que o codigo da aplicacao falhe.

```sql
CREATE TABLE subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    plan_id UUID NOT NULL REFERENCES plans(id),
    status TEXT NOT NULL CHECK (status IN ('active', 'canceled', 'expired', 'suspended')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    canceled_at TIMESTAMPTZ,
    monthly_price NUMERIC(10, 2) NOT NULL CHECK (monthly_price >= 0),
    UNIQUE (user_id, plan_id),
    CHECK (canceled_at IS NULL OR canceled_at > started_at)
);
```

### Regras

- **NOT NULL** em toda coluna que nao tem motivo para ser nula. Na duvida, NOT NULL.
- **CHECK** para validar dominio de valores (status, ranges, formatos).
- **UNIQUE** para unicidade de negocio (email, CPF, combinacoes).
- **FOREIGN KEY** para integridade referencial. Sempre defina `ON DELETE` explicito.
- Nomeie constraints explicitamente para facilitar debug: `CONSTRAINT chk_price_positive CHECK (price >= 0)`.

---

## 9. Seguranca em Migracoes

### Principio: migracoes devem ser aditivas e reversiveis

- **NUNCA** renomeie colunas diretamente em producao. Isso quebra deployments em andamento.
- **NUNCA** remova colunas sem um periodo de deprecacao (no minimo 1 release).
- **NUNCA** altere tipos de colunas diretamente. Crie coluna nova, migre dados, remova a antiga.

### Padrao seguro para renomear coluna

```
Release 1: Adicionar coluna nova + trigger de sync
Release 2: Migrar codigo para ler/escrever na nova coluna
Release 3: Backfill dados antigos
Release 4: Remover coluna antiga + trigger
```

> **Nota:** para padroes de migracao especificos do banco (CREATE INDEX CONCURRENTLY, NOT NULL com NOT VALID, etc.), consulte a referencia do banco em uso.

---

## 10. Operacoes em Massa (Bulk)

### Regra: nunca processe linha por linha

- Para insercoes em massa, use mecanismos nativos do banco (COPY, LOAD DATA, etc.) ou batch INSERT com multiplos VALUES.
- Para atualizacoes em massa, use CTEs com JOINs, nao loops na aplicacao.

### Batch INSERT

```sql
-- BOM: multiplos valores em um statement
INSERT INTO events (user_id, event_type, created_at)
VALUES
    ($1, $2, $3),
    ($4, $5, $6),
    ($7, $8, $9);
```

> **Nota:** para operacoes de bulk especificas do banco (COPY, CopyFrom com pgx, etc.), consulte a referencia do banco em uso.

---

## 11. Anti-Patterns

### Type casting implicito

```sql
-- RUIM: o indice em user_id (integer) nao sera usado
SELECT * FROM orders WHERE user_id = '42';

-- BOM: tipo correto
SELECT * FROM orders WHERE user_id = 42;
```

### SELECT sem LIMIT em tabelas grandes

```sql
-- RUIM: pode retornar milhoes de linhas
SELECT id, name FROM users WHERE status = 'active';

-- BOM: sempre limite
SELECT id, name FROM users WHERE status = 'active' LIMIT 100;
```

### OR em WHERE com colunas diferentes

```sql
-- RUIM: impede uso eficiente de indices
SELECT * FROM users WHERE email = $1 OR phone = $2;

-- BOM: UNION para usar indice em cada coluna
SELECT * FROM users WHERE email = $1
UNION
SELECT * FROM users WHERE phone = $2;
```

### NOT IN com subquery

```sql
-- RUIM: NOT IN com NULL produz resultado vazio inesperado e e lento
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blocked_users);

-- BOM: use NOT EXISTS
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.user_id = u.id);
```

> **Nota:** para anti-patterns especificos do banco (trigram indexes, COUNT(*) com pg_class, etc.), consulte a referencia do banco em uso.

---

## 12. Testando Codigo de Banco de Dados

### Principios

- Todo teste deve rodar em uma transacao que faz ROLLBACK ao final (isolamento total).
- Use fixtures explicitas. Nunca dependa de dados pre-existentes no banco de teste.
- Teste constraints: verifique que dados invalidos sao rejeitados.
- Teste queries complexas com dados realistas (volumes e distribuicoes similares a producao).

### Padrao em Go (com sqlx e testify)

```go
func TestCreateOrder(t *testing.T) {
    tx, err := db.Beginx()
    require.NoError(t, err)
    defer tx.Rollback() // SEMPRE rollback ao final

    // Fixture: criar usuario de teste
    userID := uuid.New()
    _, err = tx.Exec("INSERT INTO users (id, name, email) VALUES ($1, $2, $3)",
        userID, "Test User", "test@example.com")
    require.NoError(t, err)

    // Acao: criar pedido
    repo := NewOrderRepo(tx)
    order, err := repo.Create(ctx, userID, 99.90)

    // Verificacao
    require.NoError(t, err)
    assert.Equal(t, userID, order.UserID)
    assert.Equal(t, 99.90, order.Total)
}
```

### Testar constraints

```go
func TestCreateOrder_RejectsNegativeTotal(t *testing.T) {
    tx, err := db.Beginx()
    require.NoError(t, err)
    defer tx.Rollback()

    repo := NewOrderRepo(tx)
    _, err = repo.Create(ctx, userID, -10.00)

    // Deve falhar com violacao de CHECK constraint
    assert.Error(t, err)
    assert.Contains(t, err.Error(), "chk_total_positive")
}
```

### Testar migracoes

- Valide migracoes up e down em pipeline de CI.
- Use banco limpo, aplique todas as migracoes, valide schema final.
- Teste idempotencia: rodar a migracao duas vezes nao deve quebrar.

---

## Checklist de Revisao SQL

Ao revisar codigo que interage com banco de dados, verifique:

- [ ] Todas as queries sao parametrizadas (sem concatenacao de strings)
- [ ] Nenhum `SELECT *` em codigo de producao
- [ ] Queries em tabelas grandes tem `EXPLAIN ANALYZE` documentado
- [ ] Indices existem para colunas filtradas, ordenadas e em JOINs
- [ ] Foreign keys tem indice na coluna referenciadora
- [ ] Transacoes sao curtas e nao fazem I/O externo
- [ ] Connection pool esta configurado com limites adequados
- [ ] Migracoes sao aditivas e reversiveis
- [ ] Constraints (NOT NULL, CHECK, UNIQUE, FK) aplicadas
- [ ] Tipos de dados corretos para o banco em uso
- [ ] Operacoes em massa usam batch/mecanismo nativo, nao loops
- [ ] Paginacao usa keyset, nao OFFSET em volumes grandes
- [ ] Testes rodam em transacao com rollback
- [ ] Padroes especificos do banco foram consultados na referencia correspondente
