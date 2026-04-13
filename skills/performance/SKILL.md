---
name: performance
version: 1.0.0
description: >
  Analisa e otimiza performance de codigo, identificando gargalos, problemas de memoria, concorrencia, cache, banco de dados e I/O.
  Aplica boas praticas de performance por linguagem (Go, Java, JS, Python).
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /performance
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# performance: Analise e Otimizacao de Performance

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

> "Otimizacao prematura e a raiz de todo mal, mas ignorar performance e negligencia."
> -- Adaptado de Donald Knuth

## Filosofia

Nao otimize sem medir. Nao ignore sem entender. O objetivo e escrever codigo que seja
**correto primeiro, claro segundo e rapido quando necessario**. Porem, existem padroes
conhecidos de performance que devem ser seguidos desde o inicio — nao como otimizacao,
mas como **boa engenharia**.

---

## 1. Identificando Gargalos

Antes de otimizar qualquer coisa, identifique **onde** esta o problema.

### 1.1 CPU-bound vs I/O-bound

- **CPU-bound:** o processo gasta a maior parte do tempo em computacao (parsing, serializacao, criptografia, compressao). Solucao: algoritmos melhores, paralelismo, cache de resultados.
- **I/O-bound:** o processo gasta a maior parte do tempo esperando (banco de dados, rede, disco). Solucao: concorrencia, batching, cache, async.

### 1.2 Estrategias de Profiling

- **Go:** `pprof` (CPU, heap, goroutine, block profile). Use `net/http/pprof` em servicos HTTP.
- **Java:** JFR (Java Flight Recorder), async-profiler, VisualVM. Habilite `-XX:+FlightRecorder`.
- **Node.js:** `--prof`, `--inspect` com Chrome DevTools, `clinic.js` (flame, doctor, bubbleprof).
- **Python:** `cProfile`, `py-spy` (sampling profiler sem overhead), `memory_profiler`.

### 1.3 Regra de Ouro

Sempre profile em condicoes realistas. Microbenchmarks isolados frequentemente mentem.
Use dados de producao (ou proximos) e cargas representativas.

---

## 2. Gerenciamento de Memoria

### 2.1 Vazamentos de Memoria (Memory Leaks)

Causas comuns:
- Goroutines/threads orfas que nunca terminam
- Listeners/callbacks registrados e nunca removidos
- Caches sem limite de tamanho ou TTL
- Closures capturando referencias grandes desnecessariamente
- Conexoes abertas e nunca fechadas (DB, HTTP, WebSocket)

### 2.2 Pressao no Garbage Collector

- **Reduza alocacoes:** reutilize objetos em vez de criar novos a cada iteracao.
- **Pre-aloque slices/arrays:** se voce sabe o tamanho aproximado, use `make([]T, 0, cap)` em Go ou `ArrayList(initialCapacity)` em Java.
- **Evite boxing/unboxing:** em Java, prefira tipos primitivos sobre wrappers quando possivel.

### 2.3 Object Pooling

Use pools para objetos caros de criar e frequentemente alocados:
- **Go:** `sync.Pool` para buffers, structs temporarias.
- **Java:** pool de conexoes (HikariCP), pool de threads (`ExecutorService`).
- **Node.js:** pool de workers (`worker_threads`), pool de conexoes.

### 2.4 Reutilizacao de Buffers

```go
// Go: reutilize buffers com sync.Pool
var bufPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func process(data []byte) {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)
    // use buf...
}
```

---

## 3. Concorrencia

### 3.1 Goroutines e Threads

- **Go:** goroutines sao baratas, mas nao ilimitadas. Sempre controle o numero maximo de goroutines concorrentes com semaforos ou worker pools.
- **Java:** use `ExecutorService` com pool limitado. Nunca crie threads manualmente em producao.
- **Node.js:** o event loop e single-threaded. Use `worker_threads` para CPU-bound.

### 3.2 Connection Pools

Todo acesso a recursos externos (DB, Redis, HTTP) deve usar connection pooling:
- Defina `maxOpenConns`, `maxIdleConns` e `connMaxLifetime` no pool de banco.
- Reutilize `http.Client` com `Transport` configurado (Go) ou `HttpClient` (Java).
- Monitore conexoes ativas vs ociosas. Pool muito grande desperica recursos; muito pequeno causa contencao.

### 3.3 Worker Pools

Para processar itens de uma fila (SQS, Kafka, etc.), use um numero fixo de workers:

```go
// Go: worker pool simples
sem := make(chan struct{}, maxWorkers)
for _, item := range items {
    sem <- struct{}{}
    go func(it Item) {
        defer func() { <-sem }()
        process(it)
    }(item)
}
```

### 3.4 Evitando Contencao

- Minimize o tempo dentro de locks (`sync.Mutex`).
- Prefira estruturas lock-free quando possivel (`sync.Map` para leitura pesada, `atomic` para contadores).
- Evite locks aninhados — risco de deadlock.
- Em Java, prefira `ConcurrentHashMap` sobre `Collections.synchronizedMap`.
- Particione dados para reduzir competicao por um unico recurso.

---

## 4. Estrategias de Cache

### 4.1 Quando Usar Cache

Cache e apropriado quando:
- O dado e lido com frequencia muito maior que escrito.
- O custo de recomputar/buscar e significativamente maior que ler do cache.
- Inconsistencia temporaria e toleravel pelo negocio.

### 4.2 Invalidacao de Cache

> "Ha apenas duas coisas dificeis em ciencia da computacao: invalidacao de cache e dar nome as coisas."

Estrategias:
- **TTL (Time-To-Live):** simples, mas pode servir dados stale. Bom para dados que mudam com pouca frequencia.
- **Write-through:** atualiza cache e banco simultaneamente. Consistente, mas mais lento na escrita.
- **Write-behind:** atualiza cache imediatamente, banco de forma assincrona. Rapido, mas risco de perda.
- **Event-driven:** invalida cache via eventos (SNS/SQS). Bom para microservicos.

### 4.3 Cache Stampede (Thundering Herd)

Quando o cache expira e muitas requisicoes simultaneas tentam recomputar o valor:
- **Singleflight:** apenas uma goroutine/thread recomputa; as demais esperam (Go: `golang.org/x/sync/singleflight`).
- **Lock com fallback:** adquira um lock para recomputar; quem nao conseguir usa o valor stale.
- **Early expiration:** renove o cache antes de expirar (background refresh).

### 4.4 Cache-Aside Pattern

O padrao mais comum em microservicos:
1. Leia do cache.
2. Se cache miss, leia do banco.
3. Grave no cache com TTL.
4. Retorne o resultado.

Mantenha o cache como **auxiliar**, nao como fonte de verdade.

---

## 5. Performance de Banco de Dados

### 5.1 Connection Pooling

- Configure `maxOpenConns` proporcional ao numero de workers, nao ao numero de requisicoes.
- `maxIdleConns` deve ser proximo a `maxOpenConns` para evitar reconexoes frequentes.
- `connMaxLifetime` deve ser menor que o timeout do banco/load balancer.

### 5.2 Otimizacao de Queries

- Use `EXPLAIN ANALYZE` para entender o plano de execucao.
- Crie indices para colunas usadas em `WHERE`, `JOIN` e `ORDER BY`.
- Evite `SELECT *` — selecione apenas colunas necessarias.
- Evite N+1 queries: use `JOIN` ou batch lookup.
- Prefira queries parametrizadas para reutilizar planos de execucao.

### 5.3 Operacoes em Batch

Em vez de inserir/atualizar um registro por vez:

```sql
-- Ruim: N inserts individuais
INSERT INTO events (type, data) VALUES ('click', '{}');
INSERT INTO events (type, data) VALUES ('view', '{}');

-- Bom: batch insert
INSERT INTO events (type, data) VALUES
  ('click', '{}'),
  ('view', '{}');
```

Em Go, use `pgx.CopyFrom` para insercoes em massa. Em Java, use `jdbcTemplate.batchUpdate`.

### 5.4 Read Replicas

Para servicos com leitura pesada:
- Direcione leituras para replicas e escritas para o primario.
- Atencao ao replication lag — leituras imediatamente apos escritas podem retornar dados antigos.
- Use `RETURNING` em PostgreSQL para evitar leitura apos escrita.

---

## 6. Performance HTTP

### 6.1 Reutilizacao de Conexoes

- Sempre reutilize `http.Client` (Go) ou `HttpClient` (Java). Nunca crie um por requisicao.
- Configure `MaxIdleConnsPerHost` (Go) para evitar reconexoes em alta carga.
- Em Node.js, use `keepAlive: true` no Agent HTTP.

### 6.2 Keep-Alive

- HTTP/1.1 com `Connection: keep-alive` evita o custo de handshake TCP/TLS a cada requisicao.
- Monitore conexoes ociosas e configure timeouts adequados.

### 6.3 Compressao

- Use `gzip` ou `br` (Brotli) para respostas HTTP.
- Para APIs internas com payloads grandes, comprima no transporte.
- Cuidado: compressao adiciona latencia de CPU. Para payloads pequenos (<1KB), nao comprime.

### 6.4 HTTP/2

- Multiplexacao: multiplas requisicoes em uma unica conexao TCP.
- Header compression (HPACK) reduz overhead.
- Server push para recursos previsíveis.
- Em comunicacao interna entre servicos, avalie gRPC sobre HTTP/2.

---

## 7. Serializacao

### 7.1 JSON vs Protobuf vs MessagePack

| Formato     | Velocidade | Tamanho | Legibilidade | Uso ideal                    |
|-------------|------------|---------|--------------|------------------------------|
| JSON        | Media      | Grande  | Alta         | APIs publicas, debug         |
| Protobuf    | Alta       | Pequeno | Baixa        | Comunicacao entre servicos   |
| MessagePack | Alta       | Medio   | Baixa        | Cache, mensageria            |

### 7.2 Evitando Reflection

- **Go:** `encoding/json` usa reflection. Para hot paths, use `easyjson`, `jsoniter` ou `sonic`.
- **Java:** Jackson com anotacoes e modulos pre-compilados. Evite BeanUtils/PropertyUtils.
- **Python:** `orjson` e 10x mais rapido que `json` da stdlib.

### 7.3 Dica Pratica

Serialize uma vez, reutilize o resultado. Se o mesmo payload e enviado para multiplos destinos,
serialize uma vez e envie o `[]byte` diretamente.

---

## 8. Lazy Loading vs Eager Loading

### 8.1 Lazy Loading (Carga Preguicosa)

Carregue dados apenas quando acessados. Apropriado quando:
- Nem todos os dados sao necessarios em toda requisicao.
- O custo de carregar tudo antecipadamente e alto.
- O dado e raramente acessado.

Risco: pode causar N+1 queries se nao for cuidadoso.

### 8.2 Eager Loading (Carga Antecipada)

Carregue todos os dados relacionados de uma vez. Apropriado quando:
- Voce sabe que vai precisar dos dados relacionados.
- Quer evitar multiplas viagens ao banco.
- O volume de dados relacionados e limitado.

### 8.3 Regra Pratica

Use eager loading quando a probabilidade de uso dos dados e > 80%.
Use lazy loading quando e < 20%. Entre 20-80%, meça e decida.

---

## 9. Paginacao e Streaming

### 9.1 Nunca Carregue Tudo na Memoria

Para listas grandes, SEMPRE pagine:
- **Offset-based:** `LIMIT 20 OFFSET 40`. Simples, mas lento para offsets grandes.
- **Cursor-based:** `WHERE id > last_id LIMIT 20`. Eficiente e consistente.
- **Keyset pagination:** melhor para grandes datasets com ordenacao.

### 9.2 Streaming

Para processar grandes volumes de dados:
- Use cursores do banco de dados para ler linha a linha.
- Em Go, itere com `rows.Next()` em vez de carregar tudo com `Select`.
- Em HTTP, use `Transfer-Encoding: chunked` ou Server-Sent Events.
- Para arquivos grandes, use `io.Reader`/`io.Writer` (Go) ou streams (Node.js).

---

## 10. Processamento Assincrono

### 10.1 Mova Trabalho Pesado para Filas

Operacoes que nao precisam de resposta imediata devem ir para background:
- Envio de emails/notificacoes
- Geracao de relatorios/PDFs
- Processamento de imagens
- Integracao com sistemas externos
- Atualizacao de caches pesados

### 10.2 Timeout e Circuit Breaker

- Sempre defina timeouts em chamadas externas (HTTP, DB, Redis).
- Use circuit breaker para evitar cascata de falhas.
- Configure retry com backoff exponencial e jitter.

---

## 11. Operacoes com Strings

### 11.1 Concatenacao

- **Go:** use `strings.Builder` ou `fmt.Sprintf` em vez de `+` em loops.
- **Java:** use `StringBuilder` em loops. Nunca `+` dentro de loops.
- **Python:** use `"".join(lista)` em vez de `+` em loops.
- **JS:** template literals para poucas concatenacoes; `Array.join` para muitas.

### 11.2 Regex

- **Compile uma vez, use muitas vezes.** Nunca compile regex dentro de loops ou funcoes chamadas frequentemente.
- Em Go: `regexp.MustCompile` em variavel de pacote.
- Em Java: `Pattern.compile` em constante estatica.
- Em Python: `re.compile` fora da funcao.

### 11.3 Formatacao

Prefira formatacao tipada sobre formatacao generica:
- Go: `strconv.Itoa(n)` e mais rapido que `fmt.Sprintf("%d", n)`.
- Java: `Integer.toString(n)` e mais rapido que `String.format("%d", n)`.

---

## 12. Otimizacao de I/O

### 12.1 Buffered Readers/Writers

Sempre use leitura/escrita bufferizada para I/O de disco e rede:
- **Go:** `bufio.NewReader`, `bufio.NewWriter`.
- **Java:** `BufferedReader`, `BufferedWriter`, `BufferedInputStream`.
- **Python:** o `open()` ja e bufferizado por padrao, mas configure o tamanho.

### 12.2 Batch Writes

Agrupe escritas para reduzir syscalls e roundtrips:
- Acumule logs em buffer antes de flush.
- Agrupe insercoes no banco em batches (veja secao 5.3).
- Em SQS, use `SendMessageBatch` para ate 10 mensagens por chamada.

### 12.3 Escrita Assincrona

Para logs e metricas, use escritores assincronos com flush periodico.
Nao bloqueie o request handler para escrever logs.

---

## 13. Anti-Padroes por Linguagem

Consulte os anti-padroes especificos da linguagem do projeto em analise. Cada referencia contem:
tabela de anti-padroes comuns, exemplos detalhados, ferramentas de profiling e benchmarking.

### Auto-deteccao de Linguagem

Identifique a linguagem do projeto automaticamente:

- **Go:** presenca de `go.mod` ou `go.sum` -> consulte `references/go.md`
- **JavaScript/Node.js:** presenca de `package.json` -> consulte `references/javascript.md`
- **Java:** presenca de `pom.xml` ou `build.gradle` -> consulte `references/java.md`
- **Python:** presenca de `requirements.txt`, `pyproject.toml` ou `setup.py` -> consulte `references/python.md`

### Referencias

| Linguagem | Arquivo | Topicos Cobertos |
|---|---|---|
| Go | [references/go.md](references/go.md) | Goroutine leaks, sync.Pool, pprof, defer em loops, alocacoes desnecessarias |
| JavaScript | [references/javascript.md](references/javascript.md) | Event loop blocking, memory leaks em closures, clinic.js, async/await patterns |
| Java | [references/java.md](references/java.md) | Autoboxing, HikariCP, JFR, string concatenacao, reflection, Stream API |
| Python | [references/python.md](references/python.md) | GIL, generators vs listas, py-spy, copias desnecessarias, serializacao |

---

## 14. Benchmarking

### 14.1 Como Medir

- **Go:** `go test -bench=. -benchmem` para CPU e alocacoes.
- **Java:** JMH (Java Microbenchmark Harness) — o unico framework confiavel.
- **Node.js:** `benchmark.js` ou `tinybench`.
- **Python:** `timeit` para microbenchmarks, `pytest-benchmark` para testes.

### 14.2 O Que Comparar

- Compare **antes vs depois** da mudanca, no mesmo hardware.
- Meça **latencia** (p50, p95, p99), nao apenas media.
- Meça **throughput** (requisicoes/segundo) sob carga.
- Meça **alocacoes** (bytes alocados, numero de alocacoes).

### 14.3 Armadilhas de Microbenchmarks

- **Eliminacao de codigo morto:** o compilador pode otimizar o codigo que voce esta medindo.
- **Warmup insuficiente:** JIT compilers (Java, V8) precisam aquecer.
- **Cache do CPU quente:** dados pequenos podem caber no cache L1/L2 e dar resultados irrealistas.
- **Resultados em maquina de desenvolvimento:** nao refletem producao (CPU, memoria, concorrencia).

### 14.4 Regra

Se voce nao consegue medir a diferenca com carga real, a otimizacao provavelmente nao importa.

---

## 15. Testes de Carga

### 15.1 Ferramentas

- **k6:** script em JavaScript, otimo para APIs REST. Recomendado.
- **wrk/wrk2:** HTTP benchmarking de baixo nivel, excelente para throughput.
- **Gatling:** Java/Scala, bom para cenarios complexos.
- **Locust:** Python, bom para prototipar cenarios.

### 15.2 Padroes de Teste

- **Smoke test:** carga minima para validar que funciona.
- **Load test:** carga esperada em producao.
- **Stress test:** carga acima do esperado para encontrar o ponto de ruptura.
- **Soak test:** carga moderada por longo periodo para detectar memory leaks.
- **Spike test:** picos subitos para avaliar comportamento sob burst.

### 15.3 O Que Observar

- Latencia: p50, p95, p99 (p99 e o que os usuarios sentem).
- Taxa de erros: deve se manter < 0.1% sob carga esperada.
- Throughput: requisicoes/segundo alcancado.
- Recursos: CPU, memoria, conexoes ativas, goroutines/threads.
- Saturacao: filas crescendo, timeouts aumentando.

### 15.4 Quando Fazer

- Antes de ir para producao com um novo servico.
- Antes de mudancas significativas em hot paths.
- Periodicamente como regressao de performance.

---

## 16. Checklist de Revisao de Performance

Ao revisar codigo, verifique:

- [ ] Conexoes externas (DB, HTTP, Redis) usam pooling?
- [ ] Queries SQL tem indices adequados?
- [ ] Operacoes em lote usam batch quando possivel?
- [ ] Cache e usado onde apropriado, com TTL e limite de tamanho?
- [ ] Goroutines/threads tem limite maximo?
- [ ] Timeouts estao configurados em todas as chamadas externas?
- [ ] Strings nao sao concatenadas em loops?
- [ ] Regex sao compilados uma unica vez?
- [ ] I/O usa buffering?
- [ ] Dados grandes sao paginados ou streamed?
- [ ] Trabalho pesado e feito de forma assincrona?
- [ ] Nao ha memory leaks obvios (goroutines orfas, listeners nao removidos)?
- [ ] Serializacao no hot path usa biblioteca otimizada?
- [ ] `defer` nao esta dentro de loops?
- [ ] Pre-alocacao de slices/arrays quando o tamanho e conhecido?

---

## Procedimento de Execucao

Quando acionada, esta skill deve:

1. **Identificar a linguagem** do projeto alvo (Go, Java, JS, Python) via auto-deteccao (secao 13).
2. **Carregar a referencia** da linguagem correspondente em `references/<linguagem>.md`.
3. **Ler o codigo** relevante ao contexto (PR, task, arquivo especifico).
4. **Aplicar o checklist** da secao 16 ao codigo analisado.
5. **Identificar anti-padroes** especificos da linguagem usando a referencia carregada.
6. **Sugerir correcoes** com exemplos de codigo quando aplicavel.
7. **Priorizar** sugestoes por impacto (alto/medio/baixo) e esforco.
8. **Nao recomendar otimizacoes** que nao tenham impacto mensuravel.

Formato de saida:

```
## Analise de Performance — <arquivo ou PR>

### Problemas Encontrados

#### [ALTO] <descricao>
- **Onde:** <arquivo:linha>
- **Impacto:** <descricao do impacto>
- **Correcao sugerida:** <codigo ou descricao>

#### [MEDIO] <descricao>
...

#### [BAIXO] <descricao>
...

### Observacoes Positivas
- <praticas boas ja adotadas>

### Recomendacao Geral
<resumo e proximos passos>
```
