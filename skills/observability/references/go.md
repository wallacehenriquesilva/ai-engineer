# Observabilidade — Referencia Go

Exemplos de implementacao para servicos Go. Consulte o [SKILL.md](../SKILL.md) para conceitos, principios e checklists.

---

## 1. Logs Estruturados

### slog (stdlib Go 1.21+)

```go
slog.Info("pedido processado",
    "trace_id", traceID,
    "order_id", orderID,
    "duration_ms", elapsed.Milliseconds(),
    "items_count", len(order.Items),
)
```

### zerolog

```go
log.Info().
    Str("trace_id", traceID).
    Str("order_id", orderID).
    Int64("duration_ms", elapsed.Milliseconds()).
    Msg("pedido processado")
```

### Mascaramento de dados sensiveis

```go
// ERRADO
slog.Info("usuario autenticado", "token", bearerToken, "cpf", user.CPF)

// CORRETO
slog.Info("usuario autenticado",
    "user_id", user.ID,
    "cpf_masked", maskCPF(user.CPF), // ex: "***.***.***-42"
)
```

---

## 2. Metricas

### Middleware RED (Rate, Errors, Duration)

```go
func metricsMiddleware(next http.Handler) http.Handler {
    requestsTotal := prometheus.NewCounterVec(
        prometheus.CounterOpts{Name: "http_requests_total"},
        []string{"method", "path", "status"},
    )
    requestDuration := prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
        },
        []string{"method", "path"},
    )

    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        rw := newResponseWriter(w)
        next.ServeHTTP(rw, r)
        duration := time.Since(start).Seconds()

        requestsTotal.WithLabelValues(r.Method, r.URL.Path, strconv.Itoa(rw.statusCode)).Inc()
        requestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
    })
}
```

### Metricas de negocio customizadas

```go
// Counters de negocio
ordersProcessed := prometheus.NewCounterVec(
    prometheus.CounterOpts{Name: "business_orders_processed_total"},
    []string{"status", "payment_method"},
)

emailsSent := prometheus.NewCounterVec(
    prometheus.CounterOpts{Name: "business_emails_sent_total"},
    []string{"template", "status"},
)

// Gauge de negocio
activeSubscriptions := prometheus.NewGauge(
    prometheus.GaugeOpts{Name: "business_active_subscriptions"},
)
```

---

## 3. Tracing Distribuido (OpenTelemetry)

### Criacao de spans

```go
func (s *OrderService) ProcessOrder(ctx context.Context, orderID string) error {
    ctx, span := tracer.Start(ctx, "OrderService.ProcessOrder",
        trace.WithAttributes(
            attribute.String("order.id", orderID),
        ),
    )
    defer span.End()

    // Operacao com banco — span filho automatico via instrumentacao
    order, err := s.repo.FindByID(ctx, orderID)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, "falha ao buscar pedido")
        return fmt.Errorf("buscar pedido %s: %w", orderID, err)
    }

    span.SetAttributes(attribute.Int("order.items_count", len(order.Items)))
    return nil
}
```

### Trace ID nos logs

```go
// Extrair trace_id do contexto OTel e adicionar ao logger
spanCtx := trace.SpanContextFromContext(ctx)
logger := slog.With(
    "trace_id", spanCtx.TraceID().String(),
    "span_id", spanCtx.SpanID().String(),
)
```

---

## 4. Health Checks

```go
func (h *HealthHandler) Health(w http.ResponseWriter, r *http.Request) {
    checks := map[string]string{
        "database": h.checkDB(),
        "redis":    h.checkRedis(),
        "sqs":      h.checkSQS(),
    }

    status := http.StatusOK
    for _, v := range checks {
        if v != "ok" {
            status = http.StatusServiceUnavailable
            break
        }
    }

    w.WriteHeader(status)
    json.NewEncoder(w).Encode(checks)
}

func (h *HealthHandler) Live(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    w.Write([]byte(`{"status":"alive"}`))
}

func (h *HealthHandler) Ready(w http.ResponseWriter, r *http.Request) {
    if err := h.db.PingContext(r.Context()); err != nil {
        w.WriteHeader(http.StatusServiceUnavailable)
        return
    }
    w.WriteHeader(http.StatusOK)
}
```

---

## 5. Rastreamento de Erros

```go
slog.Error("falha ao processar pedido",
    "error", err.Error(),
    "error_type", fmt.Sprintf("%T", err),
    "trace_id", traceID,
    "order_id", orderID,
    "retry_count", retryCount,
    "queue", queueName,
    "service_version", buildVersion,
)
```

**Nunca registre apenas a mensagem de erro.** Sem contexto, o erro e inutil para investigacao.
