# Observabilidade — Referencia Python

Exemplos de implementacao para servicos Python (FastAPI, Django, etc.). Consulte o [SKILL.md](../SKILL.md) para conceitos, principios e checklists.

---

## 1. Logs Estruturados

### structlog

```python
import structlog
logger = structlog.get_logger()

logger.info("pedido processado",
    trace_id=trace_id,
    order_id=order_id,
    duration_ms=elapsed_ms,
    items_count=len(order.items),
)
```

### logging com JSON formatter (python-json-logger)

```python
import logging
from pythonjsonlogger import jsonlogger

logger = logging.getLogger(__name__)
handler = logging.StreamHandler()
handler.setFormatter(jsonlogger.JsonFormatter(
    fmt="%(asctime)s %(levelname)s %(name)s %(message)s"
))
logger.addHandler(handler)

logger.info("pedido processado", extra={
    "trace_id": trace_id,
    "order_id": order_id,
    "duration_ms": elapsed_ms,
    "items_count": len(order.items),
})
```

### Mascaramento de dados sensiveis

```python
# ERRADO
logger.info("usuario autenticado", token=bearer_token, cpf=user.cpf)

# CORRETO
logger.info("usuario autenticado",
    user_id=user.id,
    cpf_masked=mask_cpf(user.cpf),  # ex: "***.***.***-42"
)
```

---

## 2. Metricas

### Middleware RED com prometheus_client (FastAPI)

```python
from prometheus_client import Counter, Histogram
import time

REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total de requests HTTP",
    ["method", "path", "status"],
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "Duracao dos requests HTTP em segundos",
    ["method", "path"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
)

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start

    REQUEST_COUNT.labels(
        method=request.method,
        path=request.url.path,
        status=response.status_code,
    ).inc()
    REQUEST_DURATION.labels(
        method=request.method,
        path=request.url.path,
    ).observe(duration)

    return response
```

### Metricas de negocio customizadas

```python
from prometheus_client import Counter, Gauge

orders_processed = Counter(
    "business_orders_processed_total",
    "Pedidos processados",
    ["status", "payment_method"],
)

active_subscriptions = Gauge(
    "business_active_subscriptions",
    "Assinaturas ativas",
)
```

---

## 3. Tracing Distribuido (OpenTelemetry)

### Criacao de spans

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

def process_order(order_id: str) -> None:
    with tracer.start_as_current_span(
        "OrderService.process_order",
        attributes={"order.id": order_id},
    ) as span:
        order = order_repo.find_by_id(order_id)
        span.set_attribute("order.items_count", len(order.items))
```

### Tratamento de erros com spans

```python
from opentelemetry.trace import StatusCode

def process_order(order_id: str) -> None:
    with tracer.start_as_current_span(
        "OrderService.process_order",
        attributes={"order.id": order_id},
    ) as span:
        try:
            order = order_repo.find_by_id(order_id)
            span.set_attribute("order.items_count", len(order.items))
        except Exception as e:
            span.record_exception(e)
            span.set_status(StatusCode.ERROR, str(e))
            raise
```

### Trace ID nos logs

```python
from opentelemetry import trace

def get_trace_context() -> dict:
    span = trace.get_current_span()
    ctx = span.get_span_context()
    return {
        "trace_id": format(ctx.trace_id, '032x'),
        "span_id": format(ctx.span_id, '016x'),
    }

# Uso com structlog
logger = structlog.get_logger().bind(**get_trace_context())
```

---

## 4. Health Checks (FastAPI)

```python
from fastapi import FastAPI, Response

app = FastAPI()

@app.get("/health")
async def health():
    checks = {
        "database": await check_db(),
        "redis": await check_redis(),
        "sqs": await check_sqs(),
    }
    healthy = all(v == "ok" for v in checks.values())
    return Response(
        content=json.dumps(checks),
        status_code=200 if healthy else 503,
        media_type="application/json",
    )

@app.get("/live")
async def live():
    return {"status": "alive"}

@app.get("/ready")
async def ready():
    try:
        await db.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        return Response(
            content='{"status": "not ready"}',
            status_code=503,
            media_type="application/json",
        )
```

---

## 5. Rastreamento de Erros

```python
logger.error("falha ao processar pedido",
    error=str(err),
    error_type=type(err).__name__,
    trace_id=trace_id,
    order_id=order_id,
    retry_count=retry_count,
    queue=queue_name,
    service_version=build_version,
    exc_info=True,
)
```

**Nunca registre apenas a mensagem de erro.** Sem contexto, o erro e inutil para investigacao.
