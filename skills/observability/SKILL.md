---
name: observability
version: 2.0.0
description: >
  Implementa e revisa observabilidade em codigo: logs estruturados, metricas, tracing distribuido, health checks, alertas e dashboards.
  Aplica padroes agnósticos de ferramenta (DataDog, Prometheus, New Relic, etc.) nos tres pilares de observabilidade.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /observability
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Observabilidade — Guia Completo para Agentes de Codigo

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

> Postura padrao: **"Se voce nao consegue observar, voce nao consegue debugar em producao."**

Este skill orienta a implementacao e revisao de observabilidade em codigo, cobrindo os tres pilares fundamentais: **Logs**, **Metricas** e **Traces**. Todos os padroes sao agnósticos de ferramenta e aplicaveis a DataDog, Prometheus, New Relic, Grafana, Jaeger, etc.

---

## Referencia por Linguagem

Detecte a linguagem pelo repo e consulte a referencia correspondente para exemplos de implementacao:

| Arquivo detectado | Linguagem | Referencia |
|---|---|---|
| `go.mod` | Go | [references/go.md](references/go.md) |
| `package.json` | JavaScript/TypeScript | [references/javascript.md](references/javascript.md) |
| `pom.xml` / `build.gradle` | Java | [references/java.md](references/java.md) |
| `requirements.txt` / `pyproject.toml` | Python | [references/python.md](references/python.md) |

Consulte a referencia da linguagem do projeto para exemplos de implementacao detalhados. Abaixo, cada secao inclui um exemplo breve para ilustrar o conceito.

---

## 1. Logs Estruturados

### 1.1 Formato e Estrutura

Logs DEVEM ser estruturados em JSON ou pares chave-valor. Nunca use logs em texto livre (printf-style) em codigo de producao.

Campos obrigatorios em todo log:

| Campo | Descricao |
|---|---|
| `timestamp` | ISO 8601 com timezone (ex: `2026-03-31T14:30:00Z`) |
| `level` | Nivel do log (DEBUG, INFO, WARN, ERROR, FATAL) |
| `message` | Descricao curta e acionavel do evento |
| `service` | Nome do servico que emitiu o log |
| `trace_id` | ID de correlacao para rastreamento distribuido |
| `span_id` | ID do span atual (quando disponivel) |

Campos recomendados:

| Campo | Descricao |
|---|---|
| `correlation_id` | ID de correlacao de negocio (ex: order_id, user_id hash) |
| `environment` | sandbox, homolog, production |
| `version` | Versao do servico (git SHA ou semver) |
| `duration_ms` | Duracao da operacao em milissegundos |
| `error.type` | Tipo/classe do erro |
| `error.stack` | Stack trace (apenas para ERROR/FATAL) |

**Exemplo breve (Go slog):**

```go
slog.Info("pedido processado",
    "trace_id", traceID,
    "order_id", orderID,
    "duration_ms", elapsed.Milliseconds(),
)
```

### 1.2 Niveis de Log — Quando Usar Cada Um

| Nivel | Quando Usar | Exemplo |
|---|---|---|
| **DEBUG** | Detalhes internos uteis apenas durante desenvolvimento ou investigacao pontual. DESABILITADO em producao por padrao. | `DEBUG: query SQL executada em 12ms, retornou 3 linhas` |
| **INFO** | Eventos normais de negocio que confirmam o funcionamento correto do sistema. | `INFO: pedido AZUL-4521 processado com sucesso` |
| **WARN** | Situacao inesperada que NAO impede o funcionamento, mas merece atencao. Pode indicar degradacao futura. | `WARN: cache miss para chave user:123, fallback para DB` |
| **ERROR** | Falha que impede a conclusao de uma operacao especifica, mas o servico continua rodando. | `ERROR: falha ao enviar email para order_id=789, tentativa 2/3` |
| **FATAL** | Falha irrecuperavel que exige shutdown do processo. Raramente usado. | `FATAL: conexao com banco de dados perdida apos 10 retentativas` |

**Regra pratica:** Se voce precisa de um alerta, use ERROR. Se precisa investigar depois, use WARN. Se e operacao normal, use INFO.

### 1.3 O Que Logar em Cada Fronteira

| Fronteira | O Que Logar | Nivel |
|---|---|---|
| **Request recebido** | Metodo HTTP, path, headers relevantes (Accept, Content-Type), request_id | INFO |
| **Chamada externa feita** | URL/servico destino, metodo, timeout configurado, duracao, status code | INFO (sucesso) / WARN (retry) / ERROR (falha) |
| **Erro ocorrido** | Tipo do erro, mensagem, stack trace, contexto da operacao | ERROR |
| **Resposta enviada** | Status code, duracao total do request, tamanho do payload | INFO |
| **Mensagem consumida (SQS/SNS)** | Message ID, tipo do evento, fila/topico de origem | INFO |
| **Mensagem publicada** | Topico destino, tipo do evento, message ID retornado | INFO |
| **Query ao banco** | Duracao, numero de linhas afetadas (nunca a query completa em producao) | DEBUG |
| **Cache hit/miss** | Chave (sem dados sensiveis), hit ou miss, TTL | DEBUG |

### 1.4 O Que NUNCA Logar

**PROIBIDO em qualquer nivel, qualquer ambiente:**

- Senhas, hashes de senha ou tokens de autenticacao
- Numeros completos de cartao de credito (maximo: ultimos 4 digitos)
- CPF, RG ou documentos de identidade completos
- Chaves de API, secrets ou credenciais
- Dados pessoais identificaveis (PII): email, telefone, endereco completo
- Bodies de request/response completos em producao (risco de PII)
- Dados de saude, orientacao sexual, religiao ou dados sensiveis LGPD

**Alternativa segura (exemplo):**

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

### 2.1 Tipos de Metricas

| Tipo | Descricao | Quando Usar | Exemplo |
|---|---|---|---|
| **Counter** | Valor que so incrementa (resetado no restart). | Contar eventos cumulativos. | `http_requests_total`, `orders_processed_total`, `errors_total` |
| **Gauge** | Valor que sobe e desce livremente. | Estado atual de um recurso. | `active_connections`, `queue_depth`, `memory_usage_bytes` |
| **Histogram** | Distribui valores em buckets pre-definidos. Permite calcular percentis (p50, p95, p99). | Medir latencias e tamanhos. | `http_request_duration_seconds`, `response_size_bytes` |
| **Summary** | Similar ao histogram, mas calcula percentis no cliente. Nao agregavel entre instancias. | Evitar — prefira histogram na maioria dos casos. | `gc_pause_duration_seconds` |

### 2.2 Metricas RED (para Servicos)

Todo servico HTTP ou consumidor de mensagens DEVE expor as metricas RED:

| Metrica | O Que Mede | Implementacao |
|---|---|---|
| **Rate** | Requests por segundo | Counter: `http_requests_total` com label `method`, `path`, `status` |
| **Errors** | Taxa de erros (5xx / total) | Counter: `http_errors_total` ou filtro `status=~"5.."` |
| **Duration** | Latencia dos requests | Histogram: `http_request_duration_seconds` com buckets adequados |

**Exemplo breve (Go Prometheus):**

```go
requestsTotal := prometheus.NewCounterVec(
    prometheus.CounterOpts{Name: "http_requests_total"},
    []string{"method", "path", "status"},
)
```

### 2.3 Metricas USE (para Recursos)

Para cada recurso do sistema (CPU, memoria, disco, pool de conexoes, filas):

| Metrica | O Que Mede | Exemplo |
|---|---|---|
| **Utilization** | Percentual do recurso em uso | `db_connection_pool_utilization_ratio` |
| **Saturation** | Trabalho enfileirado que nao pode ser atendido | `db_connection_pool_pending_requests` |
| **Errors** | Numero de erros do recurso | `db_connection_errors_total` |

### 2.4 Metricas de Negocio Customizadas

Alem das metricas tecnicas, exporte metricas de dominio.

**Convencao de nomes:** `{dominio}_{recurso}_{acao}_{unidade}` — ex: `business_orders_processed_total`, `http_request_duration_seconds`.

---

## 3. Tracing Distribuido

### 3.1 Conceitos

- **Trace:** Representa uma requisicao completa atravessando multiplos servicos.
- **Span:** Uma unidade de trabalho dentro de um trace (ex: chamada HTTP, query ao banco).
- **Context Propagation:** Passagem automatica do trace_id/span_id entre servicos via headers (W3C Trace Context ou B3).

### 3.2 Criacao de Spans

Crie spans para operacoes significativas — nao para cada funcao:

| Criar Span | Nao Criar Span |
|---|---|
| Chamada HTTP a servico externo | Funcao utilitaria pura |
| Query ao banco de dados | Conversao de tipos |
| Publicacao/consumo de mensagem | Validacao de campos |
| Operacao de cache (Redis, DynamoDB) | Logica de negocio simples (< 1ms) |
| Chamada a API externa (Salesforce, Braze) | Getters/setters |

**Exemplo breve (Go OpenTelemetry):**

```go
ctx, span := tracer.Start(ctx, "OrderService.ProcessOrder",
    trace.WithAttributes(attribute.String("order.id", orderID)),
)
defer span.End()
```

### 3.3 Trace ID nos Logs

Sempre inclua o `trace_id` nos logs para correlacao. Isso permite saltar de um log para o trace completo na ferramenta de observabilidade.

---

## 4. Health Checks

Todo servico DEVE implementar tres endpoints de saude:

| Endpoint | Proposito | O Que Verificar | Quem Consulta |
|---|---|---|---|
| `/health` | Verificacao geral de saude | Banco de dados, cache, dependencias criticas | Load balancer, monitoramento |
| `/ready` | Pronto para receber trafego | Todas as dependencias inicializadas, migrations executadas | Kubernetes readinessProbe |
| `/live` | Processo esta vivo | Apenas que o processo responde (sem I/O externo) | Kubernetes livenessProbe |

**Regras criticas:**

- `/live` NUNCA deve verificar dependencias externas — se o banco cair, o pod nao deve ser reiniciado em loop.
- `/ready` deve retornar 503 se qualquer dependencia critica estiver indisponivel.
- `/health` deve retornar detalhes de cada dependencia com status individual.

---

## 5. Alertas

### 5.1 Principios de Alertas

- **Alerte sobre sintomas, nao causas.** Alerte sobre "taxa de erros 5xx acima de 1%" — nao sobre "uso de CPU acima de 80%".
- **Base em SLI/SLO.** Defina indicadores de nivel de servico (SLI) e objetivos (SLO), e alerte quando o error budget estiver sendo consumido rapido demais.
- **Evite fadiga de alertas.** Cada alerta deve ser acionavel — se ninguem precisa agir, remova o alerta.

### 5.2 SLI/SLO na Pratica

| SLI | SLO | Alerta |
|---|---|---|
| Disponibilidade (% requests com sucesso) | 99.9% em janela de 30 dias | Error budget consumido > 50% em 1 hora |
| Latencia p99 | < 500ms | p99 > 500ms por mais de 5 minutos |
| Taxa de sucesso de processamento de mensagens | 99.5% | Taxa de falha > 0.5% por 15 minutos |

### 5.3 Severidade de Alertas

| Severidade | Criterio | Acao |
|---|---|---|
| **P1 - Critico** | Servico indisponivel ou perda de dados | Acionar on-call imediatamente |
| **P2 - Alto** | Degradacao significativa (> 5% de erros) | Investigar em ate 30 minutos |
| **P3 - Medio** | Degradacao leve ou anomalia | Investigar no proximo horario comercial |
| **P4 - Baixo** | Informativo, tendencia preocupante | Revisar na proxima sprint |

---

## 6. Dashboards

### 6.1 Os 4 Sinais Dourados (Golden Signals)

Todo dashboard de servico DEVE mostrar, no minimo:

| Sinal | O Que Mostra | Visualizacao Recomendada |
|---|---|---|
| **Latencia** | Tempo de resposta (p50, p95, p99) | Grafico de linha com percentis |
| **Trafego** | Volume de requests por segundo | Grafico de linha / area |
| **Erros** | Taxa de erros (% e absoluto) | Grafico de linha + valor atual |
| **Saturacao** | Uso de recursos criticos (CPU, memoria, conexoes) | Gauge + grafico de linha |

### 6.2 Principios de Design de Dashboards

1. **Hierarquia visual:** Metricas mais criticas no topo, detalhes abaixo.
2. **Contexto temporal:** Sempre mostre janela de comparacao (semana anterior, deploy anterior).
3. **Linhas de referencia:** Marque SLOs e thresholds de alerta como linhas horizontais.
4. **Drill-down:** Dashboard geral do servico → dashboard de endpoint → traces individuais.
5. **Nao misture granularidades:** Nao coloque metricas de 1 minuto ao lado de metricas de 1 hora.

---

## 7. Rastreamento de Erros

### 7.1 Agrupamento e Deduplicacao

Erros devem ser agrupados para evitar ruido:

- **Agrupar por:** tipo de erro + stack trace normalizado (sem variaveis dinamicas).
- **Deduplicar:** Mesmo erro em multiplas instancias conta como 1 ocorrencia com N repeticoes.
- **Contexto minimo por erro:** trace_id, servico, versao, ambiente, timestamp, usuario (hash).

### 7.2 Informacoes de Contexto

Ao registrar um erro, sempre inclua contexto suficiente para investigacao: tipo do erro, trace_id, IDs de negocio relevantes, contagem de retentativas, fila de origem e versao do servico.

**Nunca registre apenas a mensagem de erro.** Sem contexto, o erro e inutil para investigacao.

---

## 8. Checklist de Revisao de Observabilidade

Ao implementar ou revisar codigo, verifique:

- [ ] Logs sao estruturados (JSON/key-value) e nunca em texto livre
- [ ] Niveis de log estao corretos (INFO para sucesso, ERROR para falha, nao o contrario)
- [ ] trace_id esta presente em todos os logs
- [ ] Nenhum dado sensivel esta sendo logado (PII, tokens, senhas)
- [ ] Metricas RED estao implementadas para endpoints HTTP
- [ ] Metricas RED estao implementadas para consumidores de mensagem
- [ ] Health checks implementados (/health, /ready, /live)
- [ ] /live NAO verifica dependencias externas
- [ ] Spans criados para chamadas externas (HTTP, DB, cache, filas)
- [ ] Context propagation configurado (headers W3C ou B3)
- [ ] Erros registrados com contexto suficiente para investigacao
- [ ] Metricas de negocio exportadas para operacoes criticas
- [ ] Dashboards atualizados com novos endpoints/metricas

---

## 9. Anti-Padroes Comuns

| Anti-Padrao | Problema | Correcao |
|---|---|---|
| Logar request body completo | Risco de PII, volume excessivo | Logar apenas campos relevantes e seguros |
| `log.Error` para situacoes esperadas | Fadiga de alerta, polui metricas | Usar WARN ou INFO conforme o caso |
| Metrics com alta cardinalidade (user_id como label) | Explosao de series temporais, custo | Usar labels com cardinalidade controlada (method, status, path normalizado) |
| Span para cada funcao interna | Overhead de performance, ruido | Span apenas para I/O externo e operacoes significativas |
| `/live` verificando banco de dados | Pod reiniciado em loop quando DB cai | `/live` retorna 200 sem I/O externo |
| Alertas sem runbook | Quem recebe nao sabe o que fazer | Todo alerta P1/P2 deve ter link para runbook |
| Dashboard com 50+ graficos | Ninguem olha, informacao perdida | Maximo 12 graficos por dashboard, hierarquia de drill-down |
