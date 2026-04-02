# Padroes de Teste — JavaScript/TypeScript

Referencia detalhada de implementacoes de teste para projetos JS/TS. Complementa o [SKILL.md principal](../SKILL.md).

---

## Nomenclatura

```typescript
// Formato: describe > contexto > it should
describe('UserService', () => {
  describe('createUser', () => {
    it('should return created user when data is valid', () => {})
    it('should throw ConflictError when email already exists', () => {})
    it('should throw ValidationError when name is empty', () => {})
  })
})
```

---

## Table-Driven Tests (it.each)

```typescript
describe('validateCNPJ', () => {
  const cases = [
    { name: 'CNPJ valido com mascara', input: '11.222.333/0001-81', expected: true },
    { name: 'CNPJ valido sem mascara', input: '11222333000181', expected: true },
    { name: 'CNPJ com todos digitos iguais', input: '11111111111111', expected: false },
    { name: 'CNPJ vazio', input: '', expected: false },
    { name: 'CNPJ com letras', input: '1122233300018a', expected: false },
  ]

  it.each(cases)('$name', ({ input, expected }) => {
    expect(validateCNPJ(input)).toBe(expected)
  })
})
```

---

## Test Fixtures — Builder pattern

```typescript
const buildUser = (overrides: Partial<User> = {}): User => ({
  id: randomUUID(),
  name: 'Maria Silva',
  email: 'maria@test.com',
  cnpj: '11222333000181',
  createdAt: new Date(),
  ...overrides,
})

// Uso:
const user = buildUser({ email: 'custom@test.com' })
```

**Limpeza de dados:** use `afterEach()` para truncar tabelas.

---

## Mocks com jest.mock

```typescript
// Mock de modulo inteiro
jest.mock('../services/email-service')

// Mock inline de dependencia
const mockRepo = {
  findByID: jest.fn().mockResolvedValue(testUser),
  save: jest.fn().mockResolvedValue(undefined),
}

// Verificacao de chamada
expect(mockRepo.save).toHaveBeenCalledWith(
  expect.objectContaining({ email: 'maria@test.com' })
)
```

---

## Teste de Caminhos de Erro

```typescript
it('should throw NotFoundError when user does not exist', async () => {
  const repo = { findByID: jest.fn().mockResolvedValue(null) }
  const svc = new UserService(repo)

  await expect(svc.getUser('nonexistent-id'))
    .rejects
    .toThrow(NotFoundError)
})

it('should throw when database connection fails', async () => {
  const repo = { findByID: jest.fn().mockRejectedValue(new Error('ECONNREFUSED')) }
  const svc = new UserService(repo)

  await expect(svc.getUser('user-123'))
    .rejects
    .toThrow('ECONNREFUSED')
})
```

---

## Cobertura

```bash
npx jest --coverage --coverageReporters=text
```

---

## Testando Codigo Assincrono — Callbacks e Promises

```typescript
it('should process event and call callback', async () => {
  const callback = jest.fn()
  const handler = new EventHandler(callback)

  await handler.process({ userId: '123', event: 'user.created' })

  expect(callback).toHaveBeenCalledWith(
    expect.objectContaining({ userId: '123' })
  )
})

// Com timeout para operacoes que demoram
it('should complete processing within 5 seconds', async () => {
  const result = await handler.processLargePayload(largeData)
  expect(result.status).toBe('completed')
}, 5000)  // timeout explicito
```

### Evitando flakiness

- **Use `waitFor()`** ou polling em vez de delays fixos
- **Teste o handler diretamente** em vez de publicar na fila real
- **Use timeouts explicitos** no `it()` para operacoes lentas

---

## Testando APIs HTTP (supertest)

```typescript
describe('POST /users', () => {
  it('should return 201 with valid data', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${validToken}`)
      .send({ name: 'Maria', email: 'maria@test.com' })

    expect(res.status).toBe(201)
    expect(res.body).toHaveProperty('id')
    expect(res.body.name).toBe('Maria')
  })

  it('should return 400 when name is missing', async () => {
    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${validToken}`)
      .send({ email: 'maria@test.com' })

    expect(res.status).toBe(400)
    expect(res.body.errors).toContainEqual(
      expect.objectContaining({ field: 'name' })
    )
  })

  it('should return 409 when email already exists', async () => {
    await createUser({ email: 'maria@test.com' })

    const res = await request(app)
      .post('/users')
      .set('Authorization', `Bearer ${validToken}`)
      .send({ name: 'Maria', email: 'maria@test.com' })

    expect(res.status).toBe(409)
  })
})
```

---

## Ferramentas e bibliotecas

| Ferramenta | Uso |
|---|---|
| `jest` | Framework de testes e assertions |
| `jest.mock()` | Mocking de modulos e funcoes |
| `it.each()` | Table-driven tests |
| `supertest` | Testes de APIs HTTP |
| `afterEach()` / `beforeEach()` | Setup e teardown |
| `expect().rejects.toThrow()` | Teste de erros async |
