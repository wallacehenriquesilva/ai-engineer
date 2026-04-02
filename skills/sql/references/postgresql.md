# Referencia PostgreSQL

Padroes, recursos e otimizacoes especificos do PostgreSQL.

---

## 1. CTEs (Common Table Expressions)

Use CTEs para legibilidade. No PostgreSQL 12+, CTEs simples sao inlined automaticamente (sem custo extra).

```sql
WITH active_users AS (
    SELECT id, name, email
    FROM users
    WHERE status = 'active'
    AND last_login > now() - interval '30 days'
),
user_orders AS (
    SELECT au.id, au.name, COUNT(o.id) as order_count, SUM(o.total) as total_spent
    FROM active_users au
    JOIN orders o ON o.user_id = au.id
    GROUP BY au.id, au.name
)
SELECT * FROM user_orders WHERE order_count > 5 ORDER BY total_spent DESC;
```

---

## 2. Window Functions

Essenciais para rankings, running totals, comparacoes com linhas adjacentes:

```sql
-- Ranking de clientes por gasto mensal
SELECT
    user_id,
    date_trunc('month', created_at) as month,
    SUM(total) as monthly_total,
    RANK() OVER (PARTITION BY date_trunc('month', created_at) ORDER BY SUM(total) DESC) as rank
FROM orders
GROUP BY user_id, date_trunc('month', created_at);

-- Diferenca para o mes anterior
SELECT
    user_id,
    month,
    revenue,
    revenue - LAG(revenue) OVER (PARTITION BY user_id ORDER BY month) as diff_from_previous
FROM monthly_revenue;
```

---

## 3. JSONB

Ideal para dados semi-estruturados, metadados, propriedades variaveis:

```sql
-- Criar coluna JSONB com indice GIN
ALTER TABLE events ADD COLUMN properties JSONB DEFAULT '{}';
CREATE INDEX idx_events_properties ON events USING GIN (properties);

-- Consultar campos especificos
SELECT id, properties->>'source' as source
FROM events
WHERE properties @> '{"campaign": "black-friday"}';

-- Indice parcial em campo JSONB especifico
CREATE INDEX idx_events_source ON events ((properties->>'source'))
WHERE properties->>'source' IS NOT NULL;
```

---

## 4. Array Types

Uteis para tags, listas curtas, filtros multi-valor:

```sql
-- Coluna de tags
ALTER TABLE articles ADD COLUMN tags TEXT[] DEFAULT '{}';
CREATE INDEX idx_articles_tags ON articles USING GIN (tags);

-- Buscar artigos com tag especifica
SELECT * FROM articles WHERE tags @> ARRAY['postgresql'];

-- Buscar artigos com qualquer uma das tags
SELECT * FROM articles WHERE tags && ARRAY['postgresql', 'database'];
```

---

## 5. Indices Parciais

Combinacao poderosa com consultas filtradas:

```sql
-- Indice apenas para notificacoes nao lidas (caso de uso real: notification-hub)
CREATE INDEX idx_notifications_unread
ON notifications (user_id, created_at DESC)
WHERE read_at IS NULL;

-- O otimizador usa esse indice apenas quando a query inclui WHERE read_at IS NULL
SELECT * FROM notifications
WHERE user_id = $1 AND read_at IS NULL
ORDER BY created_at DESC
LIMIT 20;
```

---

## 6. Covering Index (INCLUDE)

Inclui colunas extras que nao sao filtradas mas sao retornadas, evitando acesso a tabela (index-only scan).

```sql
CREATE INDEX idx_orders_covering ON orders (user_id, status) INCLUDE (total, created_at);
```

---

## 7. Criacao de Indice sem Downtime

```sql
-- SEMPRE use CONCURRENTLY em producao
CREATE INDEX CONCURRENTLY idx_orders_user_id ON orders (user_id);
```

**Atencao:** `CREATE INDEX CONCURRENTLY` nao pode rodar dentro de uma transacao. Configure a migration tool para executar esse statement fora de um bloco transacional.

---

## 8. Adicionar NOT NULL com Seguranca

```sql
-- 1. Adicionar constraint como NOT VALID (nao valida dados existentes)
ALTER TABLE orders ADD CONSTRAINT chk_status_not_null CHECK (status IS NOT NULL) NOT VALID;

-- 2. Validar em separado (nao bloqueia escrita)
ALTER TABLE orders VALIDATE CONSTRAINT chk_status_not_null;

-- 3. Agora pode alterar para NOT NULL (PostgreSQL reconhece a constraint)
ALTER TABLE orders ALTER COLUMN status SET NOT NULL;
ALTER TABLE orders DROP CONSTRAINT chk_status_not_null;
```

---

## 9. Backfill Seguro com Advisory Locks

Nunca faca `UPDATE ... SET` em milhoes de linhas de uma vez. Use batches:

```sql
-- Backfill em batches de 1000
WITH batch AS (
    SELECT id FROM orders
    WHERE new_column IS NULL
    ORDER BY id
    LIMIT 1000
    FOR UPDATE SKIP LOCKED
)
UPDATE orders
SET new_column = compute_value(old_column)
WHERE id IN (SELECT id FROM batch);
```

---

## 10. COPY (Insercao Massiva)

```sql
COPY events (user_id, event_type, created_at)
FROM STDIN WITH (FORMAT csv);
```

Em Go com pgx:

```go
// Usar CopyFrom para insercoes massivas
rows := [][]interface{}{
    {userID1, "signup", time.Now()},
    {userID2, "login", time.Now()},
}
copyCount, err := conn.CopyFrom(
    ctx,
    pgx.Identifier{"events"},
    []string{"user_id", "event_type", "created_at"},
    pgx.CopyFromRows(rows),
)
```

---

## 11. Batch UPDATE com CTE

```sql
-- Atualizar multiplas linhas de uma vez
WITH new_values (id, status) AS (
    VALUES
        ('uuid-1'::uuid, 'active'),
        ('uuid-2'::uuid, 'canceled'),
        ('uuid-3'::uuid, 'expired')
)
UPDATE subscriptions s
SET status = nv.status
FROM new_values nv
WHERE s.id = nv.id;
```

---

## 12. Tipos de Dados PostgreSQL

| Situacao | Use | Evite |
|---|---|---|
| Texto de tamanho variavel | `TEXT` | `VARCHAR(255)` sem motivo (no PostgreSQL, performance identica) |
| Data e hora | `TIMESTAMPTZ` (sempre com timezone) | `TIMESTAMP` sem timezone (ambiguidade) |
| Auto-incremento local | `BIGSERIAL` ou `GENERATED ALWAYS AS IDENTITY` | `SERIAL` (legado, prefira IDENTITY) |
| JSON estruturado | `JSONB` (indexavel, compacto) | `JSON` (parseado a cada acesso) |
| Enumeracoes | `TEXT` com `CHECK` constraint | `ENUM` type (dificil de alterar) |

### UUID como Primary Key

```sql
CREATE TABLE orders (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    -- ...
);
```

**Atencao:** UUIDs v4 tem fragmentacao em indices B-tree. Considere UUIDv7 (time-ordered) para tabelas com altissimo volume de insercao.

---

## 13. Niveis de Isolamento

- **Read Committed** (padrao PostgreSQL): suficiente para 95% dos casos. Use como padrao.
- **Repeatable Read**: quando precisa de snapshot consistente durante a transacao (relatorios, calculos).
- **Serializable**: quando corretude absoluta importa mais que performance (transferencias financeiras).

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- queries do relatorio aqui
COMMIT;
```

---

## 14. Connection Pooling (PgBouncer / pgxpool)

- **SEMPRE** use um connection pool (PgBouncer, pgxpool, HikariCP, SQLAlchemy pool).
- Configure limites adequados: `max_connections` do pool deve ser **menor** que `max_connections` do PostgreSQL.
- Formula inicial: `pool_size = (num_cores * 2) + num_disks` (regra do PostgreSQL wiki).
- Em microservicos, cada instancia deve ter pool pequeno (5-20 conexoes). A soma de todos os pools nao deve exceder o limite do banco.

Em Go, configure `db.SetMaxOpenConns()`, `db.SetMaxIdleConns()` e `db.SetConnMaxLifetime()`.

---

## 15. Anti-Patterns Especificos do PostgreSQL

### Indice trigram para buscas LIKE

```sql
-- RUIM: LIKE com % no inicio invalida indices B-tree
SELECT * FROM users WHERE email LIKE '%@gmail.com';

-- BOM: use indice trigram para buscas parciais
CREATE INDEX idx_users_email_trgm ON users USING GIN (email gin_trgm_ops);
SELECT * FROM users WHERE email LIKE '%@gmail.com';

-- MELHOR: se possivel, reestruture a busca
SELECT * FROM users WHERE email_domain = 'gmail.com';
```

### COUNT(*) com estimativa

```sql
-- RUIM: seq scan completo em tabela de 50M linhas
SELECT COUNT(*) FROM events;

-- ALTERNATIVA 1: estimativa (aceite imprecisao)
SELECT reltuples::bigint AS estimate
FROM pg_class WHERE relname = 'events';

-- ALTERNATIVA 2: contagem aproximada com filtro
SELECT COUNT(*) FROM events
WHERE created_at > now() - interval '24 hours';
-- (com indice em created_at, e rapido)
```
