# Observabilidade — Referencia JavaScript/TypeScript

Exemplos de implementacao para servicos JS/TS/Node.js. Consulte o [SKILL.md](../SKILL.md) para conceitos, principios e checklists.

---

## 1. Logs Estruturados

### pino

```typescript
logger.info({
  traceId,
  orderId,
  durationMs: elapsed,
  itemsCount: order.items.length,
}, 'pedido processado');
```

### winston

```typescript
logger.info('pedido processado', {
  traceId,
  orderId,
  durationMs: elapsed,
  itemsCount: order.items.length,
});
```

### Mascaramento de dados sensiveis

```typescript
// ERRADO
logger.info({ token: bearerToken, cpf: user.cpf }, 'usuario autenticado');

// CORRETO
logger.info({
  userId: user.id,
  cpfMasked: maskCPF(user.cpf), // ex: "***.***.***-42"
}, 'usuario autenticado');
```

---

## 2. Metricas

### Middleware RED com prom-client (Prometheus)

```typescript
import client from 'prom-client';

const requestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total de requests HTTP',
  labelNames: ['method', 'path', 'status'],
});

const requestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duracao dos requests HTTP em segundos',
  labelNames: ['method', 'path'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
});

function metricsMiddleware(req, res, next) {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const duration = Number(process.hrtime.bigint() - start) / 1e9;
    requestsTotal.inc({ method: req.method, path: req.route?.path || req.path, status: res.statusCode });
    requestDuration.observe({ method: req.method, path: req.route?.path || req.path }, duration);
  });
  next();
}
```

### Metricas de negocio customizadas

```typescript
const ordersProcessed = new client.Counter({
  name: 'business_orders_processed_total',
  help: 'Pedidos processados',
  labelNames: ['status', 'payment_method'],
});

const activeSubscriptions = new client.Gauge({
  name: 'business_active_subscriptions',
  help: 'Assinaturas ativas',
});
```

---

## 3. Tracing Distribuido (OpenTelemetry)

### Criacao de spans

```typescript
import { trace, SpanStatusCode } from '@opentelemetry/api';

const tracer = trace.getTracer('order-service');

async function processOrder(orderId: string): Promise<void> {
  const span = tracer.startSpan('OrderService.processOrder', {
    attributes: { 'order.id': orderId },
  });

  try {
    const order = await orderRepo.findById(orderId);
    span.setAttribute('order.items_count', order.items.length);
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: 'falha ao buscar pedido' });
    throw error;
  } finally {
    span.end();
  }
}
```

### Trace ID nos logs

```typescript
import { trace } from '@opentelemetry/api';

function getTraceContext() {
  const span = trace.getActiveSpan();
  if (!span) return {};
  const ctx = span.spanContext();
  return {
    traceId: ctx.traceId,
    spanId: ctx.spanId,
  };
}

// Uso com pino
const logger = pino().child(getTraceContext());
```

---

## 4. Health Checks (Express)

```typescript
app.get('/health', async (req, res) => {
  const checks = {
    database: await checkDB(),
    redis: await checkRedis(),
    sqs: await checkSQS(),
  };

  const healthy = Object.values(checks).every(v => v === 'ok');
  res.status(healthy ? 200 : 503).json(checks);
});

app.get('/live', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

app.get('/ready', async (req, res) => {
  try {
    await db.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch {
    res.status(503).json({ status: 'not ready' });
  }
});
```

---

## 5. Rastreamento de Erros

```typescript
logger.error({
  error: err.message,
  errorType: err.constructor.name,
  stack: err.stack,
  traceId,
  orderId,
  retryCount,
  queue: queueName,
  serviceVersion: buildVersion,
}, 'falha ao processar pedido');
```

**Nunca registre apenas a mensagem de erro.** Sem contexto, o erro e inutil para investigacao.
