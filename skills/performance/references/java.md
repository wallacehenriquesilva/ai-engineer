# Anti-Padroes de Performance — Java

Referencia especifica para projetos Java (Spring Boot, Java EE). Parte da skill `/performance`.

---

## Anti-Padroes Comuns

| Anti-padrao | Impacto | Solucao |
|---|---|---|
| Autoboxing em loops | Alocacao de objetos wrapper | Use tipos primitivos |
| String concatenacao em loops | O(n^2) de alocacoes | `StringBuilder` |
| Reflection em hot paths | 10-100x mais lento | Cache MethodHandles ou code-gen |
| `synchronized` em metodos inteiros | Contencao alta | Minimize escopo do lock |
| Stream API em hot paths | Overhead de objetos intermediarios | Use for-loop classico |

---

## Autoboxing e Unboxing

Autoboxing converte tipos primitivos em seus wrappers (`int` -> `Integer`). Em loops, isso cria milhares de objetos temporarios.

### Problema

```java
// RUIM: autoboxing em cada iteracao
Long sum = 0L;
for (long i = 0; i < 1_000_000; i++) {
    sum += i; // boxing: cria novo Long a cada soma
}

// BOM: use tipos primitivos
long sum = 0L;
for (long i = 0; i < 1_000_000; i++) {
    sum += i; // sem alocacao
}
```

### Em Colecoes

```java
// RUIM: List<Integer> forca autoboxing
List<Integer> ids = new ArrayList<>();
for (int i = 0; i < n; i++) {
    ids.add(i); // autoboxing int -> Integer
}

// BOM: use bibliotecas com colecoes primitivas
// Eclipse Collections: IntList, LongList, etc.
// ou int[] quando possivel
int[] ids = new int[n];
for (int i = 0; i < n; i++) {
    ids[i] = i;
}
```

---

## HikariCP — Connection Pooling

HikariCP e o pool de conexoes padrao do Spring Boot. Configuracao inadequada e uma causa comum de problemas de performance.

### Configuracao Recomendada

```yaml
spring:
  datasource:
    hikari:
      # Tamanho maximo do pool = numero de cores * 2 + numero de discos
      # Para a maioria dos servicos: 10-20 conexoes
      maximum-pool-size: 10
      # Manter conexoes ociosas proximas ao maximo
      minimum-idle: 10
      # Tempo maximo de vida de uma conexao (menor que timeout do DB/LB)
      max-lifetime: 1800000  # 30 minutos
      # Timeout para obter conexao do pool
      connection-timeout: 30000  # 30 segundos
      # Tempo ocioso antes de fechar conexao extra
      idle-timeout: 600000  # 10 minutos
      # Query de validacao
      connection-test-query: SELECT 1
```

### Diagnostico de Problemas

```java
// Monitore metricas do HikariCP
HikariPoolMXBean poolProxy = dataSource.getHikariPoolMXBean();
log.info("Active: {}, Idle: {}, Waiting: {}, Total: {}",
    poolProxy.getActiveConnections(),
    poolProxy.getIdleConnections(),
    poolProxy.getThreadsAwaitingConnection(),
    poolProxy.getTotalConnections());
```

### Sinais de Problema

- `ThreadsAwaitingConnection > 0` frequentemente: pool muito pequeno ou queries lentas.
- `ActiveConnections == MaximumPoolSize` constantemente: pool saturado.
- Exceptions `ConnectionNotAvailableException`: pool esgotado.

---

## Java Flight Recorder (JFR)

JFR e a ferramenta de profiling integrada da JVM com overhead minimo (<1%).

### Habilitando

```bash
# Ao iniciar a aplicacao
java -XX:+FlightRecorder \
     -XX:StartFlightRecording=duration=60s,filename=recording.jfr \
     -jar app.jar

# Ou em runtime via jcmd
jcmd <pid> JFR.start duration=60s filename=recording.jfr
```

### Eventos Importantes

| Evento | O que mostra |
|---|---|
| `jdk.CPULoad` | Uso de CPU da JVM e do sistema |
| `jdk.GCPhasePause` | Pausas do Garbage Collector |
| `jdk.ObjectAllocationInNewTLAB` | Alocacoes de objetos (hot paths) |
| `jdk.JavaMonitorEnter` | Contencao de locks |
| `jdk.ThreadSleep` / `jdk.ThreadPark` | Threads bloqueadas |
| `jdk.SocketRead` / `jdk.SocketWrite` | I/O de rede |
| `jdk.FileRead` / `jdk.FileWrite` | I/O de disco |

### Analisando

```bash
# Use JDK Mission Control (JMC) para visualizar
jmc

# Ou use jfr tool para extrair dados via CLI
jfr print --events jdk.GCPhasePause recording.jfr
jfr summary recording.jfr
```

### Em Spring Boot

```yaml
# application.yml — habilitar JFR events via Micrometer
management:
  metrics:
    export:
      jfr:
        enabled: true
```

---

## String Concatenacao em Loops

### Problema

```java
// RUIM: O(n^2) — cria novo String a cada iteracao
String result = "";
for (String item : items) {
    result += item + ","; // alocacao a cada +
}

// BOM: O(n) — StringBuilder reutiliza buffer interno
StringBuilder sb = new StringBuilder(items.size() * 20); // pre-aloca
for (String item : items) {
    if (sb.length() > 0) sb.append(',');
    sb.append(item);
}
String result = sb.toString();
```

### String.join para Casos Simples

```java
// MELHOR para join simples
String result = String.join(",", items);
```

---

## Reflection em Hot Paths

Reflection e 10-100x mais lenta que chamadas diretas. Evite em codigo executado frequentemente.

### Problema

```java
// RUIM: reflection em cada requisicao
Object value = object.getClass()
    .getMethod("getName")
    .invoke(object);
```

### Solucoes

```java
// BOM: cache de MethodHandle (quase tao rapido quanto chamada direta)
private static final MethodHandle GET_NAME;
static {
    try {
        GET_NAME = MethodHandles.lookup()
            .findVirtual(MyClass.class, "getName", MethodType.methodType(String.class));
    } catch (Exception e) {
        throw new RuntimeException(e);
    }
}

// Uso
String name = (String) GET_NAME.invoke(object);
```

```java
// BOM: use interfaces/generics em vez de reflection
interface Named {
    String getName();
}
// O compilador resolve em compile-time, sem reflection
```

### Jackson e Serializacao

```java
// Configure ObjectMapper uma unica vez (thread-safe)
private static final ObjectMapper MAPPER = new ObjectMapper()
    .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

// Reutilize em todas as serializacoes
String json = MAPPER.writeValueAsString(object);
```

---

## Concorrencia

### ConcurrentHashMap vs synchronized

```java
// RUIM: lock global em toda operacao
Map<String, Object> map = Collections.synchronizedMap(new HashMap<>());

// BOM: locks por segmento, leitura sem lock
ConcurrentHashMap<String, Object> map = new ConcurrentHashMap<>();

// Para compute atomico
map.computeIfAbsent(key, k -> expensiveComputation(k));
```

### ExecutorService

```java
// RUIM: criar Thread manualmente
new Thread(() -> process(item)).start();

// BOM: pool gerenciado
ExecutorService executor = Executors.newFixedThreadPool(
    Runtime.getRuntime().availableProcessors()
);
executor.submit(() -> process(item));

// MELHOR: Virtual Threads (Java 21+)
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
    executor.submit(() -> process(item));
}
```

---

## Stream API — Quando Evitar

```java
// Em hot paths, for-loop classico e mais rapido (sem overhead de objetos intermediarios)
// Stream:
long count = items.stream()
    .filter(i -> i.isActive())
    .mapToLong(Item::getValue)
    .sum();

// For-loop (menos alocacoes):
long count = 0;
for (Item item : items) {
    if (item.isActive()) {
        count += item.getValue();
    }
}
```

Use Stream API para legibilidade em codigo que nao e hot path. Em hot paths medidos por profiling, considere o for-loop.

---

## Benchmarking com JMH

```java
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 5, time = 1)
@Measurement(iterations = 10, time = 1)
@Fork(2)
public class MyBenchmark {

    @Benchmark
    public String stringConcat(Blackhole bh) {
        String result = "";
        for (int i = 0; i < 100; i++) {
            result += "item" + i;
        }
        return result;
    }

    @Benchmark
    public String stringBuilder(Blackhole bh) {
        StringBuilder sb = new StringBuilder(600);
        for (int i = 0; i < 100; i++) {
            sb.append("item").append(i);
        }
        return sb.toString();
    }
}
```

```bash
# Executar benchmarks JMH
mvn clean install
java -jar target/benchmarks.jar
```
