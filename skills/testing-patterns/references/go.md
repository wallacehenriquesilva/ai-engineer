# Padroes de Teste — Go

Referencia detalhada de implementacoes de teste para projetos Go. Complementa o [SKILL.md principal](../SKILL.md).

---

## Nomenclatura

```go
// Formato: Test<Funcao>_<Cenario>_<ResultadoEsperado>
func TestCreateUser_WithValidData_ReturnsCreatedUser(t *testing.T) {}
func TestCreateUser_WithDuplicateEmail_ReturnsConflictError(t *testing.T) {}
func TestCreateUser_WithEmptyName_ReturnsValidationError(t *testing.T) {}
```

---

## Table-Driven Tests (padrao idiomatico)

```go
func TestValidateCNPJ(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected bool
    }{
        {"CNPJ valido com mascara", "11.222.333/0001-81", true},
        {"CNPJ valido sem mascara", "11222333000181", true},
        {"CNPJ com todos digitos iguais", "11111111111111", false},
        {"CNPJ vazio", "", false},
        {"CNPJ com letras", "1122233300018a", false},
        {"CNPJ curto demais", "112223330001", false},
        {"CNPJ longo demais", "1122233300018111", false},
        {"CNPJ com caracteres unicode", "11.222.333/0001-8\u00e9", false},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := ValidateCNPJ(tt.input)
            assert.Equal(t, tt.expected, result)
        })
    }
}
```

---

## Test Fixtures — Factory pattern

```go
func newTestUser(overrides ...func(*User)) *User {
    u := &User{
        Name:  "Maria Silva",
        Email: "maria@test.com",
        CNPJ:  "11222333000181",
    }
    for _, fn := range overrides {
        fn(u)
    }
    return u
}

// Uso:
user := newTestUser(func(u *User) {
    u.Email = "custom@test.com"
})
```

**Limpeza de dados:** use `t.Cleanup()` para registrar funcoes de limpeza.

---

## Mocks — Padrao correto

**ERRADO — over-mocking, nao testa nada real:**
```go
// Este teste so verifica que voce chamou os mocks na ordem certa.
// Se a query SQL estiver errada, o teste passa mesmo assim.
func TestCreateUser_OverMocked(t *testing.T) {
    mockRepo := new(MockUserRepository)
    mockRepo.On("Save", mock.Anything).Return(nil)
    mockCache := new(MockCache)
    mockCache.On("Set", mock.Anything, mock.Anything).Return(nil)
    mockEventBus := new(MockEventBus)
    mockEventBus.On("Publish", mock.Anything).Return(nil)

    svc := NewUserService(mockRepo, mockCache, mockEventBus)
    err := svc.CreateUser(validUser)

    assert.NoError(t, err)
    mockRepo.AssertCalled(t, "Save", mock.Anything)  // Nao garante nada
}
```

**CORRETO — mock apenas o que e externo:**
```go
func TestCreateUser_ProperMocking(t *testing.T) {
    // Banco real (testcontainers) para o repositorio
    db := setupTestDB(t)
    repo := NewPostgresUserRepository(db)

    // Mock apenas para o servico externo de email
    mockEmailSvc := new(MockEmailService)
    mockEmailSvc.On("SendWelcome", mock.Anything).Return(nil)

    svc := NewUserService(repo, mockEmailSvc)
    user, err := svc.CreateUser(validUser)

    assert.NoError(t, err)
    assert.NotEmpty(t, user.ID)

    // Verifica que o usuario realmente esta no banco
    saved, _ := repo.FindByID(context.Background(), user.ID)
    assert.Equal(t, validUser.Email, saved.Email)
}
```

---

## Teste de Caminhos de Erro

```go
func TestGetUser_WhenDatabaseFails_ReturnsInternalError(t *testing.T) {
    repo := &failingRepo{err: errors.New("connection refused")}
    svc := NewUserService(repo)

    _, err := svc.GetUser(ctx, "user-123")

    assert.Error(t, err)
    assert.Contains(t, err.Error(), "connection refused")

    var appErr *AppError
    assert.True(t, errors.As(err, &appErr))
    assert.Equal(t, http.StatusInternalServerError, appErr.StatusCode)
}
```

---

## Isolamento com t.Parallel()

```go
func TestUserService(t *testing.T) {
    t.Parallel()  // SEMPRE adicione em testes unitarios

    t.Run("creates user successfully", func(t *testing.T) {
        t.Parallel()
        // cada sub-teste tem seu proprio setup
        svc := newTestService(t)
        // ...
    })

    t.Run("returns error for duplicate email", func(t *testing.T) {
        t.Parallel()
        svc := newTestService(t)
        // ...
    })
}
```

### Anti-padrao de isolamento

```go
// ERRADO — variavel de pacote compartilhada entre testes
var testDB *sql.DB

func TestA(t *testing.T) {
    testDB.Exec("INSERT INTO users ...")  // polui estado para TestB
}

func TestB(t *testing.T) {
    // Depende de TestA ter rodado antes? Vai quebrar em paralelo.
    rows, _ := testDB.Query("SELECT * FROM users")
}
```

```go
// CORRETO — cada teste cria seu proprio banco/schema
func TestA(t *testing.T) {
    t.Parallel()
    db := setupIsolatedDB(t)
    db.Exec("INSERT INTO users ...")
}

func TestB(t *testing.T) {
    t.Parallel()
    db := setupIsolatedDB(t)
    rows, _ := db.Query("SELECT * FROM users")
}
```

---

## Cobertura

```bash
go test ./... -coverprofile=coverage.out -covermode=atomic
go tool cover -func=coverage.out
```

---

## Testando Codigo Assincrono — Filas SQS (ca-starters-go)

```go
func TestProcessUserCreatedEvent(t *testing.T) {
    // Setup: banco real, mock do servico externo
    db := setupTestDB(t)
    mockSegment := new(MockSegmentClient)
    mockSegment.On("Track", mock.Anything).Return(nil)

    handler := NewUserCreatedHandler(db, mockSegment)

    // Simula mensagem SQS
    msg := &sqs.Message{
        Body: aws.String(`{"user_id":"123","email":"test@test.com"}`),
    }

    err := handler.Handle(context.Background(), msg)

    assert.NoError(t, err)
    mockSegment.AssertCalled(t, "Track", mock.MatchedBy(func(e SegmentEvent) bool {
        return e.UserID == "123" && e.Event == "User Created"
    }))
}
```

### Evitando flakiness

- **NUNCA use `time.Sleep()`** — use channels, WaitGroups ou assertions com timeout
- **Use `assert.Eventually()`** (testify) para condicoes que levam tempo
- **Teste o handler diretamente** em vez de publicar na fila real (quando possivel)

---

## Testando APIs HTTP (httptest)

```go
func TestCreateUserEndpoint(t *testing.T) {
    t.Parallel()

    router := setupTestRouter(t)

    t.Run("returns 201 with valid data", func(t *testing.T) {
        body := `{"name":"Maria","email":"maria@test.com"}`
        req := httptest.NewRequest(http.MethodPost, "/users", strings.NewReader(body))
        req.Header.Set("Content-Type", "application/json")
        req.Header.Set("Authorization", "Bearer "+validToken)

        rec := httptest.NewRecorder()
        router.ServeHTTP(rec, req)

        assert.Equal(t, http.StatusCreated, rec.Code)
        assert.Equal(t, "application/json", rec.Header().Get("Content-Type"))

        var resp UserResponse
        json.Unmarshal(rec.Body.Bytes(), &resp)
        assert.NotEmpty(t, resp.ID)
        assert.Equal(t, "Maria", resp.Name)
    })

    t.Run("returns 400 when name is missing", func(t *testing.T) {
        body := `{"email":"maria@test.com"}`
        req := httptest.NewRequest(http.MethodPost, "/users", strings.NewReader(body))
        req.Header.Set("Content-Type", "application/json")
        req.Header.Set("Authorization", "Bearer "+validToken)

        rec := httptest.NewRecorder()
        router.ServeHTTP(rec, req)

        assert.Equal(t, http.StatusBadRequest, rec.Code)
    })

    t.Run("returns 401 without auth token", func(t *testing.T) {
        body := `{"name":"Maria","email":"maria@test.com"}`
        req := httptest.NewRequest(http.MethodPost, "/users", strings.NewReader(body))
        req.Header.Set("Content-Type", "application/json")

        rec := httptest.NewRecorder()
        router.ServeHTTP(rec, req)

        assert.Equal(t, http.StatusUnauthorized, rec.Code)
    })
}
```

---

## Testando Banco de Dados (testcontainers-go)

### Setup com testcontainers

```go
func setupTestDB(t *testing.T) *sql.DB {
    t.Helper()

    ctx := context.Background()
    container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
        ContainerRequest: testcontainers.ContainerRequest{
            Image:        "postgres:16-alpine",
            ExposedPorts: []string{"5432/tcp"},
            Env: map[string]string{
                "POSTGRES_DB":       "testdb",
                "POSTGRES_USER":     "test",
                "POSTGRES_PASSWORD": "test",
            },
            WaitingFor: wait.ForListeningPort("5432/tcp"),
        },
        Started: true,
    })
    require.NoError(t, err)

    t.Cleanup(func() { container.Terminate(ctx) })

    host, _ := container.Host(ctx)
    port, _ := container.MappedPort(ctx, "5432")

    dsn := fmt.Sprintf("postgres://test:test@%s:%s/testdb?sslmode=disable", host, port.Port())
    db, err := sql.Open("postgres", dsn)
    require.NoError(t, err)

    // Roda migrations
    runMigrations(db)

    return db
}
```

### Testes de repositorio

```go
func TestUserRepository_Save(t *testing.T) {
    db := setupTestDB(t)
    repo := NewPostgresUserRepository(db)

    t.Run("inserts user successfully", func(t *testing.T) {
        user := newTestUser()

        err := repo.Save(context.Background(), user)

        assert.NoError(t, err)
        saved, err := repo.FindByID(context.Background(), user.ID)
        assert.NoError(t, err)
        assert.Equal(t, user.Email, saved.Email)
    })

    t.Run("fails on duplicate email", func(t *testing.T) {
        user1 := newTestUser(func(u *User) { u.Email = "dup@test.com" })
        user2 := newTestUser(func(u *User) { u.Email = "dup@test.com" })

        repo.Save(context.Background(), user1)
        err := repo.Save(context.Background(), user2)

        assert.Error(t, err)
        assert.Contains(t, err.Error(), "unique")
    })
}
```

### Testando transacoes

```go
func TestTransferFunds_RollsBackOnError(t *testing.T) {
    db := setupTestDB(t)
    repo := NewAccountRepository(db)

    from := newTestAccount(func(a *Account) { a.Balance = 1000 })
    to := newTestAccount(func(a *Account) { a.Balance = 500 })
    repo.Save(ctx, from)
    repo.Save(ctx, to)

    // Tenta transferir mais do que o saldo
    err := repo.Transfer(ctx, from.ID, to.ID, 2000)

    assert.Error(t, err)

    // Verifica que NENHUM saldo foi alterado (rollback completo)
    fromAfter, _ := repo.FindByID(ctx, from.ID)
    toAfter, _ := repo.FindByID(ctx, to.ID)
    assert.Equal(t, int64(1000), fromAfter.Balance)
    assert.Equal(t, int64(500), toAfter.Balance)
}
```

### Testando migrations

```bash
# Verifica que todas as migrations up/down funcionam
migrate -path ./migrations -database "$DB_URL" up
migrate -path ./migrations -database "$DB_URL" down
migrate -path ./migrations -database "$DB_URL" up  # deve funcionar novamente
```

---

## TDD — Exemplo pratico do ciclo (Go)

```go
// PASSO 1 (RED): Escreva o teste
func TestCalculateDiscount_GoldCustomer_Returns20Percent(t *testing.T) {
    discount := CalculateDiscount("gold", 100.00)
    assert.Equal(t, 20.00, discount)
}
// Resultado: FALHA (CalculateDiscount nao existe)

// PASSO 2 (GREEN): Implementacao minima
func CalculateDiscount(tier string, amount float64) float64 {
    if tier == "gold" {
        return amount * 0.20
    }
    return 0
}
// Resultado: PASSA

// PASSO 3 (RED): Proximo teste
func TestCalculateDiscount_SilverCustomer_Returns10Percent(t *testing.T) {
    discount := CalculateDiscount("silver", 100.00)
    assert.Equal(t, 10.00, discount)
}
// Resultado: FALHA

// PASSO 4 (GREEN): Expande a implementacao
func CalculateDiscount(tier string, amount float64) float64 {
    rates := map[string]float64{
        "gold":   0.20,
        "silver": 0.10,
    }
    rate, ok := rates[tier]
    if !ok {
        return 0
    }
    return amount * rate
}
// Resultado: PASSA

// PASSO 5 (REFACTOR): Melhora sem alterar comportamento
// Extrair constantes, melhorar nomes, etc.
```

---

## Ferramentas e bibliotecas

| Ferramenta | Uso |
|---|---|
| `testify` (assert/require/mock) | Assertions e mocks |
| `httptest` | Testes de handlers HTTP |
| `testcontainers-go` | Banco de dados real em container |
| `t.Parallel()` | Execucao paralela de testes |
| `t.Cleanup()` | Limpeza automatica de recursos |
| `t.Helper()` | Melhora stacktrace em helpers |
