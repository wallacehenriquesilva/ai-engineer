---
name: rest-api
version: 1.0.0
description: >
  Skill de design e revisao de APIs RESTful. Cobre convencoes de nomenclatura, metodos HTTP, codigos de status, paginacao, versionamento, validacao, autenticacao, rate limiting, idempotencia e anti-patterns.
  Use para implementar novas APIs ou revisar APIs existentes.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /rest-api
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# REST API Design

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

Uma API e um contrato. Mudancas que quebram esse contrato sao inaceitaveis. Toda decisao de design deve priorizar consistencia, previsibilidade e compatibilidade retroativa.

Esta skill define as regras e padroes para projetar, implementar e revisar APIs RESTful.

---

## 1. Convencoes de Nomenclatura

### 1.1 URLs usam substantivos no plural

Recursos sao sempre substantivos no plural. Nunca use verbos na URL.

```
# Correto
GET    /users
GET    /users/123
GET    /users/123/orders
POST   /users

# Errado
GET    /getUsers
POST   /createUser
GET    /user/list
DELETE /deleteUser/123
```

### 1.2 Recursos aninhados

Use aninhamento para expressar relacionamentos hierarquicos. Limite a no maximo 2 niveis de profundidade.

```
# Correto — ate 2 niveis
GET /users/123/orders
GET /users/123/orders/456

# Evite — 3+ niveis; use query params ou recurso de topo
GET /users/123/orders/456/items/789   # ruim
GET /order-items?order_id=456          # melhor
```

### 1.3 Convencoes de formato

- URLs: `kebab-case` (ex: `/order-items`, `/payment-methods`)
- Query params: `snake_case` (ex: `?page_size=20&sort_by=created_at`)
- Body JSON: `snake_case` para campos (ex: `{ "first_name": "Ana" }`)
- Headers customizados: `X-Custom-Header` ou prefixo da aplicacao

### 1.4 Acoes que nao sao CRUD

Quando uma operacao nao se encaixa em CRUD, use sub-recursos ou verbos como ultimo recurso:

```
# Preferivel — sub-recurso
POST /orders/123/cancellation
POST /users/123/password-reset

# Aceitavel — verbo explicito quando nao ha alternativa
POST /reports/generate
```

---

## 2. Metodos HTTP

Cada metodo tem semantica precisa. Respeite-a rigorosamente.

| Metodo  | Semantica                  | Idempotente | Corpo na req | Corpo na resp |
|---------|----------------------------|-------------|--------------|---------------|
| GET     | Leitura de recurso         | Sim         | Nao          | Sim           |
| POST    | Criacao de recurso         | Nao         | Sim          | Sim           |
| PUT     | Substituicao completa      | Sim         | Sim          | Sim           |
| PATCH   | Atualizacao parcial        | Nao*        | Sim          | Sim           |
| DELETE  | Remocao de recurso         | Sim         | Nao          | Opcional      |
| HEAD    | Igual ao GET sem corpo     | Sim         | Nao          | Nao           |
| OPTIONS | Metodos permitidos / CORS  | Sim         | Nao          | Sim           |

*PATCH pode ser idempotente dependendo da implementacao, mas o protocolo nao garante.

### Regras

- **GET** nunca altera estado. E seguro e cacheavel.
- **POST** cria um novo recurso. Retorna `201 Created` com `Location` header.
- **PUT** substitui o recurso inteiro. Se um campo for omitido, ele e removido ou zerado.
- **PATCH** atualiza apenas os campos enviados. Campos omitidos permanecem inalterados.
- **DELETE** remove o recurso. Retorna `204 No Content` em caso de sucesso.

---

## 3. Codigos de Status HTTP

Use o codigo correto para cada situacao. Nunca retorne `200` com um corpo de erro.

### Sucesso (2xx)

| Codigo | Quando usar                                                    |
|--------|----------------------------------------------------------------|
| 200    | Requisicao bem-sucedida com corpo de resposta (GET, PATCH, PUT)|
| 201    | Recurso criado com sucesso (POST). Inclua header `Location`.   |
| 204    | Sucesso sem corpo de resposta (DELETE, PUT sem retorno).        |

### Erro do cliente (4xx)

| Codigo | Quando usar                                                              |
|--------|--------------------------------------------------------------------------|
| 400    | Requisicao malformada — JSON invalido, tipo errado, campo obrigatorio.   |
| 401    | Nao autenticado — token ausente, expirado ou invalido.                   |
| 403    | Autenticado, mas sem permissao para o recurso ou acao.                   |
| 404    | Recurso nao encontrado. Use tambem quando o usuario nao tem acesso       |
|        | e voce nao quer revelar a existencia do recurso.                         |
| 409    | Conflito — recurso ja existe, violacao de unicidade, estado inconsistente.|
| 422    | Entidade nao processavel — validacao de regras de negocio falhou.        |
| 429    | Rate limit excedido. Inclua header `Retry-After`.                        |

### Erro do servidor (5xx)

| Codigo | Quando usar                                                    |
|--------|----------------------------------------------------------------|
| 500    | Erro interno inesperado. Nunca exponha stack traces.           |
| 502    | Resposta invalida de um servico upstream (gateway/proxy).      |
| 503    | Servico temporariamente indisponivel (manutencao, sobrecarga). |

---

## 4. Formato de Resposta de Erro

Toda resposta de erro deve seguir uma estrutura consistente. O consumidor da API deve poder parsear erros programaticamente.

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Os dados enviados nao passaram na validacao.",
    "details": [
      {
        "field": "email",
        "code": "INVALID_FORMAT",
        "message": "O email informado nao e valido."
      },
      {
        "field": "age",
        "code": "OUT_OF_RANGE",
        "message": "A idade deve ser entre 18 e 120."
      }
    ],
    "request_id": "req_abc123def456"
  }
}
```

### Regras para erros

- **Sempre** inclua um `code` legivel por maquina (enum ou constante).
- **Sempre** inclua uma `message` legivel por humanos.
- **Nunca** exponha stack traces, caminhos de arquivos, queries SQL ou detalhes internos.
- **Sempre** inclua `request_id` para correlacao com logs e tracing.
- Para erros de validacao (400/422), inclua o array `details` com campo e motivo.
- O formato de erro deve ser identico em todos os endpoints da API.

---

## 5. Paginacao

### 5.1 Paginacao baseada em cursor (recomendada)

Ideal para datasets grandes ou que mudam frequentemente. Evita problemas de dados duplicados ou perdidos entre paginas.

```
GET /users?cursor=eyJpZCI6MTIzfQ&page_size=20
```

Resposta:

```json
{
  "data": [...],
  "pagination": {
    "next_cursor": "eyJpZCI6MTQzfQ",
    "has_next": true,
    "page_size": 20
  }
}
```

### 5.2 Paginacao baseada em offset

Mais simples, util para datasets pequenos e estaveis. Ineficiente para tabelas grandes.

```
GET /users?page=3&page_size=20
```

Resposta:

```json
{
  "data": [...],
  "pagination": {
    "page": 3,
    "page_size": 20,
    "total_count": 157,
    "total_pages": 8
  }
}
```

### 5.3 Link headers (opcional)

Inclua headers `Link` conforme RFC 8288 para navegacao:

```
Link: <https://api.example.com/users?cursor=abc>; rel="next",
      <https://api.example.com/users?cursor=xyz>; rel="prev"
```

### Regras de paginacao

- Defina um `page_size` maximo (ex: 100) e um padrao (ex: 20).
- Sempre retorne metadados de paginacao no corpo da resposta.
- Use cursor-based para feeds, timelines e tabelas grandes.
- Use offset-based apenas quando o usuario precisa acessar paginas arbitrarias.

---

## 6. Filtragem, Ordenacao e Busca

### 6.1 Filtragem

Use query params para filtros simples:

```
GET /orders?status=pending&created_after=2025-01-01
GET /users?role=admin&active=true
```

### 6.2 Ordenacao

Use `sort_by` e `sort_order`:

```
GET /users?sort_by=created_at&sort_order=desc
GET /orders?sort_by=total,created_at&sort_order=desc,asc
```

### 6.3 Busca

Use `q` ou `search` para busca textual:

```
GET /users?q=ana+silva
GET /products?search=notebook&category=electronics
```

### Regras

- Documente todos os campos filtraveis, ordenaveis e buscaveis.
- Valide nomes de campos — retorne `400` para campos inexistentes.
- Tenha um `sort_by` padrao (normalmente `created_at desc`).

---

## 7. Versionamento

### 7.1 Versionamento por URL (recomendado)

Mais explicito e facil de rotear, cachear e debugar.

```
GET /v1/users
GET /v2/users
```

### 7.2 Versionamento por header

Mais "puro" do ponto de vista REST, mas mais dificil de debugar e cachear.

```
GET /users
Accept: application/vnd.myapi.v2+json
```

### Quando criar uma nova versao

- Remocao de campos obrigatorios da resposta.
- Mudanca de tipo de um campo (ex: string para int).
- Mudanca de semantica de um endpoint.
- Remocao de um endpoint.

### O que NAO exige nova versao

- Adicao de campos opcionais na resposta.
- Adicao de novos endpoints.
- Adicao de novos query params opcionais.

### Regra de ouro

> Adicionar e seguro. Remover ou alterar quebra o contrato.

---

## 8. Validacao de Entrada

### 8.1 Request body

- Valide tipos, formatos e limites de todos os campos.
- Rejeite campos desconhecidos (ou ignore silenciosamente, mas seja consistente).
- Retorne `400` para JSON malformado.
- Retorne `422` para dados validos sintaticamente mas invalidos pelas regras de negocio.

### 8.2 Query params

- Valide tipos e faixas de valores.
- Defina valores padrao para params opcionais.
- Retorne `400` para params com valores invalidos.

### 8.3 Path params

- Valide formato (ex: UUID, numerico).
- Retorne `404` se o formato for valido mas o recurso nao existir.
- Retorne `400` se o formato for invalido (ex: letras onde se espera numero).

### 8.4 Headers

- Valide `Content-Type` — rejeite com `415 Unsupported Media Type` se nao for suportado.
- Valide headers obrigatorios da aplicacao (ex: `X-Tenant-Id`).

---

## 9. Autenticacao

### 9.1 Bearer Token (JWT)

Padrao mais comum para APIs modernas. O token e enviado no header `Authorization`.

```
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
```

### 9.2 API Key

Util para integracao machine-to-machine. Envie no header, nunca na URL.

```
X-API-Key: sk_live_abc123def456
```

### 9.3 OAuth2

Use para autorizacao delegada (apps de terceiros acessando recursos do usuario).

- Authorization Code Flow para apps com backend.
- PKCE para SPAs e apps mobile.
- Client Credentials para comunicacao servico-a-servico.

### Regras de autenticacao

- Sempre use HTTPS. Nunca transmita credenciais em texto plano.
- Nunca coloque tokens ou API keys em query params (ficam em logs de servidor e historico do navegador).
- Retorne `401` para credenciais ausentes ou invalidas.
- Retorne `403` para credenciais validas sem permissao suficiente.
- Inclua `WWW-Authenticate` header na resposta `401`.

---

## 10. Rate Limiting

Proteja a API contra abuso e garanta disponibilidade para todos os consumidores.

### Headers de resposta

```
X-RateLimit-Limit: 1000        # limite de requisicoes na janela
X-RateLimit-Remaining: 847     # requisicoes restantes na janela
X-RateLimit-Reset: 1672531200  # timestamp Unix de quando o limite reseta
Retry-After: 30                # segundos ate poder tentar novamente (em respostas 429)
```

### Regras

- Retorne `429 Too Many Requests` quando o limite for excedido.
- Sempre inclua `Retry-After` na resposta `429`.
- Documente os limites por tier de cliente (ex: free, pro, enterprise).
- Considere limites por endpoint (endpoints pesados com limites menores).
- Use sliding window ou token bucket como algoritmo.

---

## 11. CORS (Cross-Origin Resource Sharing)

### Headers necessarios

```
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Authorization, Content-Type, X-Request-ID
Access-Control-Max-Age: 86400
Access-Control-Expose-Headers: X-RateLimit-Limit, X-RateLimit-Remaining
```

### Regras

- Nunca use `Access-Control-Allow-Origin: *` em APIs autenticadas.
- Responda requisicoes `OPTIONS` (preflight) com `204` e os headers corretos.
- Configure `Access-Control-Max-Age` para reduzir preflight requests.
- Exponha apenas os headers que o frontend realmente precisa.

---

## 12. Content Negotiation

### Request

```
Content-Type: application/json    # formato do corpo enviado
Accept: application/json          # formato desejado na resposta
```

### Regras

- Suporte `application/json` como formato padrao.
- Retorne `415 Unsupported Media Type` se o `Content-Type` nao for suportado.
- Retorne `406 Not Acceptable` se o `Accept` nao puder ser atendido.
- Se nenhum `Accept` for enviado, assuma `application/json`.

---

## 13. Idempotencia

### O problema

Retentativas de requisicoes (timeout, falha de rede) podem causar duplicacao. Um POST executado duas vezes cria dois recursos.

### A solucao: chave de idempotencia

O cliente envia um identificador unico no header:

```
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

### Comportamento esperado

1. Primeira requisicao com a chave: processe normalmente, armazene o resultado.
2. Requisicao repetida com a mesma chave: retorne o resultado armazenado sem reprocessar.
3. A chave deve expirar apos um periodo (ex: 24h).

### Regras

- Implemente idempotencia para **todos** os endpoints POST que criam recursos.
- PUT e DELETE ja sao idempotentes por definicao.
- GET e seguro e cacheavel — nao precisa de chave.
- Armazene a chave com o status code e corpo da resposta original.

---

## 14. HATEOAS (Hypermedia)

HATEOAS (Hypermedia as the Engine of Application State) adiciona links navegaveis nas respostas.

### Quando usar

- APIs publicas consumidas por terceiros que precisam de auto-descoberta.
- APIs com fluxos complexos de estado (ex: workflow de pedido).
- Quando o custo de implementacao se justifica pelo beneficio.

### Quando NAO usar

- APIs internas entre microservicos (acoplamento ja e conhecido).
- APIs simples de CRUD sem fluxos de estado.

### Exemplo

```json
{
  "id": 123,
  "status": "pending",
  "total": 99.90,
  "_links": {
    "self": { "href": "/orders/123" },
    "cancel": { "href": "/orders/123/cancellation", "method": "POST" },
    "payment": { "href": "/orders/123/payment", "method": "POST" }
  }
}
```

---

## 15. Documentacao da API

### OpenAPI / Swagger

Toda API deve ter uma especificacao OpenAPI (v3.0+) atualizada.

### Regras

- Documente **todos** os endpoints, parametros, request bodies e respostas.
- Inclua **exemplos reais** em cada endpoint (nao apenas o schema).
- Documente todos os codigos de erro possiveis com seus formatos.
- Mantenha a spec versionada junto com o codigo (spec-as-code).
- Gere a documentacao a partir da spec, nao o contrario.
- Inclua exemplos de autenticacao e fluxos comuns.

### Exemplo de documentacao de endpoint

```yaml
paths:
  /users:
    post:
      summary: Cria um novo usuario
      operationId: createUser
      tags: [users]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateUserRequest'
            example:
              first_name: "Ana"
              last_name: "Silva"
              email: "ana@example.com"
      responses:
        '201':
          description: Usuario criado com sucesso
          headers:
            Location:
              schema:
                type: string
              example: /users/123
          content:
            application/json:
              example:
                id: 123
                first_name: "Ana"
                last_name: "Silva"
                email: "ana@example.com"
                created_at: "2025-06-15T10:30:00Z"
        '400':
          $ref: '#/components/responses/BadRequest'
        '409':
          $ref: '#/components/responses/Conflict'
        '422':
          $ref: '#/components/responses/UnprocessableEntity'
```

---

## 16. Health Check Endpoints

Toda API deve expor endpoints de saude para orquestradores (Kubernetes, load balancers).

### Endpoints obrigatorios

| Endpoint  | Proposito                                              | Usado por             |
|-----------|--------------------------------------------------------|-----------------------|
| `/health` | Verificacao geral de saude do servico.                 | Load balancers        |
| `/ready`  | Indica se o servico esta pronto para receber trafego.  | Kubernetes readiness  |
| `/live`   | Indica se o processo esta vivo (nao travou).           | Kubernetes liveness   |

### Comportamento

- `/health` verifica dependencias (banco, cache, filas) e retorna `200` ou `503`.
- `/ready` retorna `200` quando o servico terminou de inicializar e pode processar.
- `/live` retorna `200` se o processo esta respondendo (mesmo que dependencias estejam fora).

### Formato de resposta

```json
{
  "status": "healthy",
  "checks": {
    "database": { "status": "up", "latency_ms": 3 },
    "redis": { "status": "up", "latency_ms": 1 },
    "sqs": { "status": "up", "latency_ms": 5 }
  },
  "version": "1.2.3",
  "uptime_seconds": 86400
}
```

### Regras

- Health checks NAO devem exigir autenticacao.
- Health checks devem responder rapido (timeout de 5s no maximo).
- Nao inclua informacoes sensiveis na resposta (versao do SO, IPs internos).

---

## 17. Anti-Patterns

### 17.1 Verbos na URL

```
# Errado
POST /api/createUser
GET  /api/getOrderById?id=123
PUT  /api/updateUserProfile

# Correto
POST   /api/users
GET    /api/orders/123
PATCH  /api/users/123
```

### 17.2 Retornar 200 com corpo de erro

```
# Errado — consumidor nao consegue diferenciar sucesso de falha pelo status code
HTTP/1.1 200 OK
{
  "success": false,
  "error": "User not found"
}

# Correto
HTTP/1.1 404 Not Found
{
  "error": {
    "code": "USER_NOT_FOUND",
    "message": "Usuario nao encontrado."
  }
}
```

### 17.3 Nomenclatura inconsistente

```
# Errado — mistura de convencoes
GET /users
GET /Order
GET /product-categories
GET /paymentMethods

# Correto — tudo plural, kebab-case
GET /users
GET /orders
GET /product-categories
GET /payment-methods
```

### 17.4 Ignorar paginacao

```
# Errado — retorna todos os registros
GET /users  ->  [...100.000 usuarios...]

# Correto — paginado por padrao
GET /users  ->  { "data": [...20 usuarios...], "pagination": {...} }
```

### 17.5 Expor detalhes internos em erros

```
# Errado
{
  "error": "NullPointerException at UserService.java:142",
  "query": "SELECT * FROM users WHERE id = '1; DROP TABLE users;--'"
}

# Correto
{
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "Erro interno. Tente novamente ou entre em contato com o suporte.",
    "request_id": "req_abc123"
  }
}
```

### 17.6 Usar o metodo HTTP errado

```
# Errado — GET com efeito colateral
GET /users/123/delete

# Errado — POST para leitura
POST /users/search  (quando um GET com query params bastaria)

# Correto
DELETE /users/123
GET    /users?q=ana
```

### 17.7 Nao versionar a API

Sem versionamento, qualquer mudanca e potencialmente uma breaking change para todos os consumidores. Sempre versione desde o primeiro dia.

### 17.8 Retornar arrays no topo da resposta

```
# Errado — nao e extensivel (nao da para adicionar metadados depois)
[
  { "id": 1, "name": "Ana" },
  { "id": 2, "name": "Bruno" }
]

# Correto — envelope com data permite adicionar paginacao, metadados etc.
{
  "data": [
    { "id": 1, "name": "Ana" },
    { "id": 2, "name": "Bruno" }
  ]
}
```

---

## Checklist de Revisao

Ao revisar ou implementar uma API, valide cada item:

- [ ] URLs usam substantivos no plural e kebab-case
- [ ] Metodos HTTP estao corretos para cada operacao
- [ ] Codigos de status sao precisos (sem 200 com erro)
- [ ] Respostas de erro seguem o formato padrao com code, message e request_id
- [ ] Paginacao esta implementada para endpoints que retornam listas
- [ ] Validacao de entrada cobre body, query params, path params e headers
- [ ] Autenticacao esta implementada e documentada
- [ ] Rate limiting esta configurado com headers apropriados
- [ ] CORS esta configurado corretamente para os origins permitidos
- [ ] Idempotencia esta implementada para endpoints POST criticos
- [ ] Health checks (/health, /ready, /live) estao expostos
- [ ] Documentacao OpenAPI esta completa com exemplos
- [ ] Versionamento esta definido desde o primeiro endpoint
- [ ] Nenhum anti-pattern da secao 17 esta presente
