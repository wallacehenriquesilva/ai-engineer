# Padroes de Teste — Python

Referencia detalhada de implementacoes de teste para projetos Python. Complementa o [SKILL.md principal](../SKILL.md).

---

## Nomenclatura

```python
# Formato: test_<funcao>_<cenario>_<resultado>
def test_create_user_with_valid_data_returns_created_user():
    pass

def test_create_user_with_duplicate_email_raises_conflict_error():
    pass

def test_create_user_with_empty_name_raises_validation_error():
    pass
```

---

## Table-Driven Tests (pytest.mark.parametrize)

```python
import pytest

@pytest.mark.parametrize("description,input_val,expected", [
    ("CNPJ valido com mascara", "11.222.333/0001-81", True),
    ("CNPJ valido sem mascara", "11222333000181", True),
    ("CNPJ com todos digitos iguais", "11111111111111", False),
    ("CNPJ vazio", "", False),
    ("CNPJ com letras", "1122233300018a", False),
])
def test_validate_cnpj(description, input_val, expected):
    assert validate_cnpj(input_val) == expected, description
```

---

## Test Fixtures — Factory Boy

```python
class UserFactory(factory.Factory):
    class Meta:
        model = User

    name = "Maria Silva"
    email = factory.Sequence(lambda n: f"user{n}@test.com")
    cnpj = "11222333000181"

# Uso:
user = UserFactory(email="custom@test.com")
```

**Limpeza de dados:** use fixtures do pytest com `yield` para setup/teardown.

```python
@pytest.fixture
def db_session():
    session = create_test_session()
    yield session
    session.rollback()
    session.close()
```

---

## Mocks com unittest.mock

```python
from unittest.mock import Mock, patch, MagicMock

# Mock de dependencia
def test_create_user_sends_welcome_email():
    email_service = Mock()
    repo = Mock()
    repo.save.return_value = test_user

    svc = UserService(repo, email_service)
    svc.create_user(valid_user)

    email_service.send_welcome.assert_called_once_with(valid_user.email)

# Patch de modulo
@patch('myapp.services.email_client')
def test_with_patched_module(mock_email):
    mock_email.send.return_value = True
    result = process_registration(user_data)
    assert result.email_sent is True
```

---

## Teste de Caminhos de Erro

```python
import pytest

def test_get_user_raises_not_found_when_missing():
    repo = Mock()
    repo.find_by_id.return_value = None
    svc = UserService(repo)

    with pytest.raises(NotFoundError):
        svc.get_user("nonexistent-id")

def test_get_user_raises_on_db_failure():
    repo = Mock()
    repo.find_by_id.side_effect = ConnectionError("ECONNREFUSED")
    svc = UserService(repo)

    with pytest.raises(ConnectionError, match="ECONNREFUSED"):
        svc.get_user("user-123")
```

---

## Cobertura

```bash
pytest --cov=src --cov-report=term-missing
```

---

## Testando APIs HTTP (FastAPI + httpx / Django DRF)

### FastAPI com httpx

```python
from httpx import AsyncClient
from myapp.main import app

@pytest.mark.asyncio
async def test_create_user_returns_201():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/users", json={
            "name": "Maria",
            "email": "maria@test.com"
        }, headers={"Authorization": f"Bearer {valid_token}"})

    assert response.status_code == 201
    assert response.json()["name"] == "Maria"
    assert "id" in response.json()

@pytest.mark.asyncio
async def test_create_user_returns_400_when_name_missing():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/users", json={
            "email": "maria@test.com"
        }, headers={"Authorization": f"Bearer {valid_token}"})

    assert response.status_code == 400
```

### Django REST Framework

```python
from rest_framework.test import APIClient

def test_create_user_returns_201():
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {valid_token}")

    response = client.post("/users/", {
        "name": "Maria",
        "email": "maria@test.com"
    }, format="json")

    assert response.status_code == 201
    assert response.data["name"] == "Maria"
```

---

## Testando Banco de Dados

### Com pytest e testcontainers

```python
import testcontainers.postgres

@pytest.fixture(scope="session")
def postgres_container():
    with testcontainers.postgres.PostgresContainer("postgres:16-alpine") as pg:
        yield pg

@pytest.fixture
def db_session(postgres_container):
    engine = create_engine(postgres_container.get_connection_url())
    Base.metadata.create_all(engine)
    session = Session(engine)
    yield session
    session.rollback()
    session.close()

def test_save_user(db_session):
    repo = UserRepository(db_session)
    user = UserFactory()

    repo.save(user)

    saved = repo.find_by_email(user.email)
    assert saved is not None
    assert saved.name == user.name
```

---

## Ferramentas e bibliotecas

| Ferramenta | Uso |
|---|---|
| `pytest` | Framework de testes |
| `pytest.mark.parametrize` | Table-driven tests |
| `unittest.mock` / `Mock` / `patch` | Mocking |
| `Factory Boy` | Geracao de dados de teste |
| `httpx` / `AsyncClient` | Testes de APIs async (FastAPI) |
| `APIClient` (DRF) | Testes de APIs Django |
| `testcontainers` | Banco de dados real em container |
| `pytest.fixture` com `yield` | Setup/teardown |
| `pytest.raises` | Teste de excecoes |
