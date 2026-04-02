# Observabilidade — Referencia Java

Exemplos de implementacao para servicos Java/Spring Boot. Consulte o [SKILL.md](../SKILL.md) para conceitos, principios e checklists.

---

## 1. Logs Estruturados (SLF4J + Logback / Log4j2)

### MDC para contexto automatico

```java
// Adicionar contexto no inicio do request (filtro/interceptor)
MDC.put("traceId", traceId);
MDC.put("orderId", orderId);

log.info("pedido processado em {}ms com {} itens",
    elapsed, order.getItems().size());

// Limpar MDC ao final do request
MDC.clear();
```

### Configuracao de JSON layout (logback-spring.xml)

```xml
<appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
  <encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <includeMdcKeyName>traceId</includeMdcKeyName>
    <includeMdcKeyName>orderId</includeMdcKeyName>
    <includeMdcKeyName>environment</includeMdcKeyName>
  </encoder>
</appender>
```

### Mascaramento de dados sensiveis

```java
// ERRADO
log.info("usuario autenticado token={} cpf={}", bearerToken, user.getCpf());

// CORRETO
log.info("usuario autenticado userId={} cpfMasked={}",
    user.getId(), maskCpf(user.getCpf())); // ex: "***.***.***-42"
```

---

## 2. Metricas

### Middleware RED com Micrometer

```java
@Configuration
public class MetricsConfig {

    @Bean
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }
}

// No controller ou servico
@Timed(value = "http.request.duration", extraTags = {"method", "POST", "path", "/orders"})
@PostMapping("/orders")
public ResponseEntity<Order> createOrder(@RequestBody OrderRequest request) {
    // ...
}
```

### Metricas customizadas com Micrometer

```java
@Component
public class OrderMetrics {
    private final Counter ordersProcessed;
    private final Gauge activeSubscriptions;

    public OrderMetrics(MeterRegistry registry) {
        this.ordersProcessed = Counter.builder("business.orders.processed.total")
            .tag("status", "success")
            .register(registry);

        this.activeSubscriptions = Gauge.builder("business.active.subscriptions",
            subscriptionService, SubscriptionService::countActive)
            .register(registry);
    }

    public void orderProcessed(String status, String paymentMethod) {
        Counter.builder("business.orders.processed.total")
            .tag("status", status)
            .tag("payment_method", paymentMethod)
            .register(registry)
            .increment();
    }
}
```

---

## 3. Tracing Distribuido (OpenTelemetry / Micrometer Tracing)

### Com anotacoes @WithSpan

```java
@WithSpan("OrderService.processOrder")
public void processOrder(@SpanAttribute("order.id") String orderId) {
    Span span = Span.current();
    Order order = orderRepository.findById(orderId)
        .orElseThrow(() -> {
            span.setStatus(StatusCode.ERROR, "pedido nao encontrado");
            return new OrderNotFoundException(orderId);
        });
    span.setAttribute("order.items_count", order.getItems().size());
}
```

### Criacao manual de spans

```java
Tracer tracer = GlobalOpenTelemetry.getTracer("order-service");

public void processOrder(String orderId) {
    Span span = tracer.spanBuilder("OrderService.processOrder")
        .setAttribute("order.id", orderId)
        .startSpan();

    try (Scope scope = span.makeCurrent()) {
        Order order = orderRepository.findById(orderId)
            .orElseThrow(() -> new OrderNotFoundException(orderId));
        span.setAttribute("order.items_count", order.getItems().size());
    } catch (Exception e) {
        span.recordException(e);
        span.setStatus(StatusCode.ERROR, e.getMessage());
        throw e;
    } finally {
        span.end();
    }
}
```

### Trace ID nos logs via MDC

```java
// Spring Boot com Micrometer Tracing — automatico via application.yml
// logging.pattern.level: "%5p [${spring.application.name},%X{traceId},%X{spanId}]"

// Ou manualmente via filtro
@Component
public class TraceFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request,
            HttpServletResponse response, FilterChain chain) throws Exception {
        Span span = Span.current();
        MDC.put("traceId", span.getSpanContext().getTraceId());
        MDC.put("spanId", span.getSpanContext().getSpanId());
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove("traceId");
            MDC.remove("spanId");
        }
    }
}
```

---

## 4. Health Checks (Spring Boot Actuator)

```java
// application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info
  endpoint:
    health:
      show-details: always
      group:
        liveness:
          include: livenessState
        readiness:
          include: readinessState,db,redis

// Custom health indicator
@Component
public class SqsHealthIndicator extends AbstractHealthIndicator {
    private final AmazonSQS sqsClient;

    @Override
    protected void doHealthCheck(Health.Builder builder) {
        try {
            sqsClient.getQueueUrl("my-queue");
            builder.up().withDetail("sqs", "ok");
        } catch (Exception e) {
            builder.down(e);
        }
    }
}
```

**Endpoints expostos pelo Actuator:**

| Endpoint | Proposito |
|---|---|
| `/actuator/health` | Health check geral com detalhes |
| `/actuator/health/liveness` | Liveness probe (sem I/O externo) |
| `/actuator/health/readiness` | Readiness probe (com dependencias) |

---

## 5. Rastreamento de Erros

```java
log.error("falha ao processar pedido orderId={} retryCount={} queue={} version={}",
    orderId, retryCount, queueName, buildVersion, exception);

// Com MDC (contexto automatico em todos os logs)
MDC.put("orderId", orderId);
MDC.put("retryCount", String.valueOf(retryCount));
log.error("falha ao processar pedido", exception);
```

**Nunca registre apenas a mensagem de erro.** Sem contexto, o erro e inutil para investigacao.
