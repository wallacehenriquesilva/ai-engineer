---
name: testing-patterns
version: 1.1.0
description: >
  Guia abrangente de padroes de teste para agentes de IA que escrevem e revisam testes automatizados. Cobre testes unitarios, integracao, e2e, table-driven tests, mocks, fixtures, edge cases, caminhos de erro, isolamento, cobertura, codigo assincrono, APIs HTTP, operacoes de banco de dados e workflow TDD.
  Postura padrão: se não esta testado, está quebrado.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /testing-patterns
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# testing-patterns: Padroes de Teste para Agentes de IA

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

**Postura padrao: se nao esta testado, esta quebrado.**

Este skill define os padroes, convencoes e estrategias que o agente DEVE seguir ao escrever, revisar ou sugerir testes automatizados. Todas as decisoes de teste devem ser guiadas por estes principios.

---

## Referencias por linguagem

Detecte a linguagem pelo repositorio e consulte a referencia apropriada para exemplos detalhados de implementacao:

| Indicador no repo | Referencia |
|---|---|
| `go.mod` | [Go](references/go.md) — table-driven tests, testify, httptest, testcontainers-go |
| `package.json` | [JavaScript/TypeScript](references/javascript.md) — Jest, describe/it, supertest, jest.mock |
| `pom.xml` ou `build.gradle` | [Java](references/java.md) — JUnit 5, @ParameterizedTest, Mockito, MockMvc, Testcontainers |
| `requirements.txt` ou `pyproject.toml` | [Python](references/python.md) — pytest, parametrize, unittest.mock, fixtures |

As secoes abaixo sao **agnósticas de linguagem**. Para codigo de exemplo especifico, consulte o arquivo de referencia correspondente.

---

## 1. Quando usar cada tipo de teste

### 1.1 Testes Unitarios

Testes unitarios validam uma unica unidade de logica (funcao, metodo, classe) de forma isolada.

**Quando usar:**
- Logica de negocio pura (calculos, validacoes, transformacoes)
- Funcoes utilitarias e helpers
- Parsing e formatacao de dados
- State machines e fluxos de decisao
- Qualquer funcao que recebe entrada e produz saida sem efeitos colaterais

**Quando NAO usar:**
- Para testar integracao com banco de dados real
- Para validar contratos HTTP completos
- Para verificar fluxos end-to-end que cruzam multiplos servicos

**Proporcao esperada:** 70-80% dos testes devem ser unitarios.

### 1.2 Testes de Integracao

Testes de integracao validam a interacao entre dois ou mais componentes reais.

**Quando usar:**
- Queries e mutations no banco de dados (repositorios, DAOs)
- Consumidores SQS processando mensagens reais
- Chamadas HTTP entre servicos (com o servico real ou testcontainers)
- Interacao com cache (Redis, DynamoDB)
- Validacao de migrations de banco de dados

**Quando NAO usar:**
- Para testar logica de negocio pura (use unitario)
- Para validar fluxos de usuario completos (use e2e)

**Proporcao esperada:** 15-25% dos testes devem ser de integracao.

### 1.3 Testes End-to-End (E2E)

Testes e2e validam o sistema inteiro do ponto de vista do usuario/consumidor.

**Quando usar:**
- Fluxos criticos de negocio (criacao de conta, processamento de pagamento)
- Validacao de contratos de API publica
- Smoke tests apos deploy
- Fluxos que cruzam multiplos servicos

**Quando NAO usar:**
- Para cada caso de borda (use unitario)
- Para validar logica interna de componentes
- Como substituto de testes unitarios e de integracao

**Proporcao esperada:** 5-10% dos testes devem ser e2e.

---

## 2. Convencoes de nomenclatura de testes

### Principio fundamental: descreva O QUE, nao COMO

O nome do teste deve descrever o comportamento esperado, nao a implementacao.

**ERRADO:**
```
TestCallsDatabaseAndReturnsUser
TestUsesRedisCache
TestCallsSendGridAPI
```

**CORRETO:**
```
TestReturnsUserWhenValidIDProvided
TestReturnsErrorWhenUserNotFound
TestSendsWelcomeEmailAfterRegistration
```

### Padrao geral

Independente da linguagem, siga o formato: `<Funcao>_<Cenario>_<ResultadoEsperado>`

Exemplos de nomenclatura especificos por linguagem estao nos arquivos de referencia.

---

## 3. Table-Driven Tests

Table-driven tests sao o padrao preferido para testar multiplas variacoes de entrada/saida com a mesma logica de teste. Reduzem duplicacao e facilitam adicionar novos casos.

### Quando usar

- Funcoes com multiplas combinacoes de entrada/saida
- Validacoes (CNPJ, email, CPF, etc.)
- Parsing e formatacao
- Qualquer logica com mais de 3 cenarios de teste similares

### Estrutura geral

1. Defina uma lista de casos com: `nome`, `entrada`, `saida esperada`
2. Itere sobre os casos executando o mesmo bloco de teste
3. Cada caso deve ter um nome descritivo para facilitar debug

Exemplos completos de implementacao: consulte o arquivo de referencia da linguagem.

---

## 4. Mock vs Dependencias Reais

### Quando usar mocks

- Servicos externos (APIs de terceiros: SendGrid, Twilio, Segment, Braze)
- Componentes com latencia alta ou custo por chamada
- Servicos que nao estao sob seu controle
- Clock/tempo (para testes deterministicos)
- Geradores de ID aleatorio (para testes reproduziveis)

### Quando usar dependencias reais

- Banco de dados (use testcontainers ou banco em memoria)
- Cache Redis (use testcontainers)
- Filas SQS (use localstack ou testcontainers)
- Logica de negocio interna do proprio servico
- Repositorios e DAOs — SEMPRE teste contra banco real

### Anti-padroes de over-mocking

O principal anti-padrao e mockar a coisa que voce quer testar. Se voce mocka o repositorio para testar o repositorio, o teste nao garante nada. Se a query SQL estiver errada, o teste passa mesmo assim.

### Regra de ouro

> Se voce esta mockando a coisa que voce quer testar, voce nao esta testando nada.
> Mocks sao para isolar fronteiras, nao para evitar setup.

Exemplos de over-mocking vs mocking correto: consulte o arquivo de referencia da linguagem.

---

## 5. Test Fixtures e Gerenciamento de Dados de Teste

### Principios

1. **Cada teste cria seus proprios dados** — nunca dependa de dados pre-existentes
2. **Use factories/builders** em vez de construtores manuais
3. **Limpe apos cada teste** — truncate ou rollback de transacao
4. **Fixtures compartilhadas sao aceitaveis** para dados de referencia imutaveis (ex: tabelas de lookup)

### Limpeza de dados (resumo por linguagem)

- **Go:** use `t.Cleanup()` para registrar funcoes de limpeza
- **Java:** use `@AfterEach` ou transacoes com rollback (`@Transactional`)
- **JS/TS:** use `afterEach()` para truncar tabelas
- **Python:** use fixtures do pytest com `yield` para setup/teardown

Exemplos de factories/builders: consulte o arquivo de referencia da linguagem.

---

## 6. Checklist de Edge Cases

Todo teste de funcao que recebe entrada externa DEVE considerar os seguintes cenarios:

### Valores nulos e vazios
- [ ] `null` / `nil` / `None` / `undefined`
- [ ] String vazia `""`
- [ ] Array/slice vazio `[]`
- [ ] Map/objeto vazio `{}`
- [ ] Zero numerico `0`
- [ ] Ponteiro nulo (Go: `*Type` com valor nil)

### Valores de fronteira (boundary)
- [ ] Valor minimo permitido
- [ ] Valor maximo permitido
- [ ] Um acima do maximo (overflow)
- [ ] Um abaixo do minimo (underflow)
- [ ] Primeiro e ultimo elemento de uma lista
- [ ] Lista com exatamente 1 elemento
- [ ] Datas: limites de mes (28/29/30/31), virada de ano, horario de verao

### Unicode e caracteres especiais
- [ ] Acentos e caracteres latinos (`"cafe"`, `"Sao Paulo"`)
- [ ] Emojis (`"Ola 👋"`)
- [ ] Caracteres CJK (chines, japones, coreano)
- [ ] Caracteres de controle (`\n`, `\t`, `\0`)
- [ ] SQL injection patterns (`'; DROP TABLE users; --`)
- [ ] HTML/XSS patterns (`<script>alert(1)</script>`)
- [ ] Strings muito longas (10K+ caracteres)

### Entradas grandes
- [ ] Listas com 10.000+ elementos
- [ ] Payloads de 1MB+
- [ ] Paginacao com offset/limit extremos

### Acesso concorrente
- [ ] Duas goroutines/threads escrevendo no mesmo recurso
- [ ] Race conditions em cache (read-after-write)
- [ ] Deadlocks em transacoes de banco
- [ ] Idempotencia de operacoes (mesma requisicao processada 2x)

---

## 7. Teste de Caminhos de Erro

**Regra: para cada caminho feliz, deve haver pelo menos um teste de caminho de erro.**

### O que testar

- Erros de validacao de entrada
- Erros de autenticacao/autorizacao (401, 403)
- Recurso nao encontrado (404)
- Conflitos de estado (409)
- Erros de timeout em chamadas externas
- Erros de conexao com banco de dados
- Erros de serializacao/desserializacao (JSON malformado)
- Erros de rate limiting (429)
- Erros internos do servidor (500)

Exemplos de testes de erro: consulte o arquivo de referencia da linguagem.

---

## 8. Isolamento de Testes

### Principios inviolaveis

1. **Sem estado compartilhado** — cada teste comeca com estado limpo
2. **Sem dependencia de ordem** — testes devem passar em qualquer ordem
3. **Sem dependencia temporal** — nao use `time.Sleep()` ou delays fixos
4. **Sem dependencia de ambiente** — nao dependa de variaveis de ambiente do CI
5. **Paralelo por padrao** — todos os testes unitarios devem rodar em paralelo

### Anti-padroes de isolamento

- Variavel global/de pacote compartilhada entre testes
- Testes que dependem de outro teste ter rodado antes
- Setup unico para multiplos testes que modificam estado
- Uso de banco de dados compartilhado sem isolamento de transacao

Exemplos de isolamento correto vs incorreto: consulte o arquivo de referencia da linguagem.

---

## 9. Cobertura de Testes

### O que medir (metricas significativas)

- **Cobertura de branches** — todas as ramificacoes de `if/else`, `switch`, `select` foram exercitadas?
- **Cobertura de caminhos de erro** — todos os `return err` foram testados?
- **Cobertura de logica de negocio** — as regras criticas do dominio estao cobertas?
- **Mutation testing** — os testes realmente detectam mudancas no codigo? (uso avancado)

### O que NAO perseguir (metricas de vaidade)

- **100% de cobertura de linhas** — leva a testes frageis e sem valor
- **Cobertura de getters/setters** — nao agrega valor
- **Cobertura de codigo gerado** — DTOs, protobuf, mocks
- **Cobertura de constantes e enums** — trivial e desnecessario

### Metas recomendadas

| Tipo de codigo | Meta minima | Meta ideal |
|---|---|---|
| Logica de negocio/dominio | 85% | 95% |
| Controllers/handlers HTTP | 70% | 85% |
| Repositorios/DAOs | 80% | 90% |
| Utilitarios/helpers | 90% | 100% |
| Codigo de infraestrutura (config, DI) | 50% | 70% |
| Codigo gerado | 0% (ignorar) | 0% (ignorar) |

### Comandos para verificar cobertura

Consulte o arquivo de referencia da linguagem para o comando especifico.

---

## 10. Testando Codigo Assincrono

### Principios gerais

1. **NUNCA use `time.Sleep()` ou delays fixos** — use mecanismos de sincronizacao (channels, WaitGroups, assertions com timeout, polling)
2. **Teste o handler diretamente** em vez de publicar na fila real (quando possivel)
3. **Use timeouts explicitos** para operacoes que podem travar
4. **Verifique chamadas com matchers** — nao apenas se foi chamado, mas com os argumentos corretos

### Cenarios comuns

- Consumidores SQS processando mensagens
- Callbacks e promises
- Publicacao de eventos SNS
- Workers em background

Exemplos de implementacao: consulte o arquivo de referencia da linguagem.

### Padrao para evitar flakiness em testes async

1. **NUNCA use `time.Sleep()`** — use channels, WaitGroups ou assertions com timeout
2. **Use `assert.Eventually()`** (Go testify) ou equivalente para condicoes que levam tempo
3. **Use `waitFor()` ou polling** em vez de delays fixos
4. **Teste o handler diretamente** em vez de publicar na fila real (quando possivel)

---

## 11. Testando APIs HTTP

### O que DEVE ser testado em todo endpoint

- [ ] Status code correto para cada cenario (200, 201, 400, 401, 403, 404, 409, 500)
- [ ] Headers de resposta (Content-Type, cache headers)
- [ ] Corpo da resposta (estrutura JSON, campos obrigatorios)
- [ ] Validacao de entrada (campos obrigatorios, tipos, limites)
- [ ] Autenticacao/autorizacao (token invalido, token expirado, sem permissao)
- [ ] Paginacao (primeira pagina, ultima pagina, pagina invalida)
- [ ] Idempotencia (POST duplicado, PUT repetido)

Exemplos de testes HTTP: consulte o arquivo de referencia da linguagem.

---

## 12. Testando Operacoes de Banco de Dados

### Principios

1. **Use banco real** (testcontainers) — nunca mock o banco
2. **Cada teste roda em transacao com rollback** (ou truncate apos)
3. **Teste migrations separadamente** — garanta que up/down funcionam
4. **Teste constraints** — unique, not null, foreign keys, check constraints

### O que testar

- INSERT com dados validos
- INSERT com violacao de constraint (unique, not null, FK)
- SELECT com filtros e paginacao
- UPDATE parcial e total
- DELETE com cascata e restricoes
- Transacoes com rollback em caso de erro
- Migrations up e down

### Testando migrations

```bash
# Verifica que todas as migrations up/down funcionam
migrate -path ./migrations -database "$DB_URL" up
migrate -path ./migrations -database "$DB_URL" down
migrate -path ./migrations -database "$DB_URL" up  # deve funcionar novamente
```

Exemplos de setup com testcontainers e testes de repositorio: consulte o arquivo de referencia da linguagem.

---

## 13. Workflow TDD (Red-Green-Refactor)

### O ciclo

1. **RED** — Escreva um teste que falha. O teste descreve o comportamento desejado.
2. **GREEN** — Escreva o codigo minimo para o teste passar. Nao otimize, nao generalize.
3. **REFACTOR** — Melhore o codigo mantendo todos os testes verdes. Elimine duplicacao, melhore nomes, extraia funcoes.

### Regras do agente ao aplicar TDD

1. **Nunca escreva codigo de producao sem um teste que o motive**
2. **Escreva apenas um teste por vez** — nao acumule testes vermelhos
3. **O teste deve falhar pelo motivo certo** — se falha por erro de compilacao antes de testar a logica, corrija a compilacao primeiro
4. **Commits atomicos:** um commit por ciclo red-green-refactor
5. **Nao refatore enquanto testes estiverem vermelhos**

Exemplo pratico do ciclo TDD: consulte o arquivo de referencia da linguagem.

---

## 14. Resumo de Regras para o Agente

Ao escrever ou revisar testes, o agente DEVE seguir estas regras:

1. **Todo codigo de producao novo deve ter testes correspondentes**
2. **Testes devem cobrir o caminho feliz E os caminhos de erro**
3. **Use table-driven tests para multiplas variacoes de entrada**
4. **Mock apenas dependencias externas — nunca mock o que voce quer testar**
5. **Cada teste deve ser independente e rodar em paralelo**
6. **Nomes de testes descrevem comportamento, nao implementacao**
7. **Use factories/builders para criar dados de teste**
8. **Sempre verifique edge cases: null, vazio, fronteira, unicode, concorrencia**
9. **Testes de banco de dados usam banco real (testcontainers), nunca mocks**
10. **Testes de API validam status code, headers, corpo e erros**
11. **Codigo assincrono e testado via handler direto, sem Sleep()**
12. **Cobertura de branches e mais importante que cobertura de linhas**
13. **Se um bug e encontrado, primeiro escreva o teste que o reproduz, depois corrija**
14. **Nao persiga 100% de cobertura — persiga 100% de confianca na logica critica**
