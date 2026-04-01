# Runbook: Nova Integração

Fluxo para implementar uma nova integração com serviço externo (ex: novo consumer SQS, novo webhook, nova API de terceiro).

---

## Quando usar

- Nova integração com serviço externo (Braze, Segment, Salesforce, etc.)
- Novo consumer SQS para eventos de outro serviço
- Novo webhook endpoint recebendo dados de fora
- Nova chamada HTTP para API de terceiro

## Checklist pré-implementação

Antes de implementar, valide que existe:

### Infraestrutura
- [ ] SNS topic existe? (ou precisa criar no repo `-infra`)
- [ ] SQS queue existe? (ou precisa criar)
- [ ] Permissões IAM configuradas? (IRSA / Vault policy)
- [ ] Variáveis de ambiente documentadas?
- [ ] Secrets no Vault? (API keys, tokens)

### Contrato
- [ ] Schema do evento/payload documentado
- [ ] Campos obrigatórios vs opcionais definidos
- [ ] Formato de data/hora combinado
- [ ] Comportamento esperado para campos nulos/vazios

### Observabilidade
- [ ] Métricas de sucesso/falha definidas (DataDog)
- [ ] Dashboard existente ou necessário?
- [ ] Alertas configurados?

## Passo a passo

### 1. Verificar se é multi-repo

Integrações frequentemente envolvem 2 repos: app + infra.

| O que precisa | Repo |
|--------------|------|
| SNS topic, SQS queue, IAM | `terraform/<service>-infra` |
| Consumer, controller, client | `go/<service>` ou `java/<service>` |

Se multi-repo → use `engineer-multi` ou implemente em ordem: **infra primeiro, app depois**.

### 2. Infraestrutura (se necessário)

```hcl
# Exemplo: novo SQS consumer
module "sqs_new_event" {
  source = "github.com/ContaAzul/terraform-modules//sqs"
  name   = "<service>-<event-name>"
  # ...
}
```

Deploy infra em sandbox/homolog ANTES de implementar o app.

### 3. Implementação do consumer/client

Para Go (ca-starters-go):

```go
// internal/consumer/<event_name>.go
type EventNameConsumer struct {
    // dependencies
}

func NewEventNameConsumer(/* deps */) *EventNameConsumer {
    return &EventNameConsumer{/* deps */}
}

func (c *EventNameConsumer) Handle(ctx context.Context, msg *sqs.Message) error {
    // 1. Parse payload
    // 2. Validate required fields
    // 3. Process business logic
    // 4. Return nil (ACK) or error (NACK/retry)
}
```

### 4. Testes obrigatórios

| Tipo | O que testar |
|------|-------------|
| Unitário | Parse do payload, validação, lógica de negócio |
| Integração | Consumer processa mensagem real do SQS (localstack ou mock) |
| Edge cases | Payload incompleto, duplicado, fora de ordem |
| Erro | Retry behavior, dead letter queue, circuit breaker |

### 5. Validação em sandbox

- Publique um evento manualmente no SNS de sandbox
- Verifique que o consumer processou (logs no DataDog)
- Verifique que o efeito colateral aconteceu (banco, API, etc.)

### 6. Documentação

Atualize o `CLAUDE.md` do repo com:
- Novo consumer/endpoint listado
- Variáveis de ambiente adicionadas
- Dependências externas
