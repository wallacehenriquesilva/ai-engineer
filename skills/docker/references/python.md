# Dockerfile — Python (FastAPI)

Exemplo completo de Dockerfile multi-stage para aplicacoes Python/FastAPI com imagem final slim.

```dockerfile
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

COPY . .

FROM python:3.12-slim AS runtime

RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app
COPY --from=builder /install /usr/local
COPY --from=builder /build .

USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Notas

- Use `python:X.Y-slim` em vez de Alpine — muitas dependencias Python tem problemas com musl/Alpine.
- `--no-cache-dir` evita armazenar cache do pip na imagem.
- `--prefix=/install` isola as dependencias para copia limpa no estagio de runtime.
- Para projetos com `pyproject.toml`, copie `pyproject.toml` e `poetry.lock`/`uv.lock` primeiro.
- O healthcheck usa `urllib.request` da stdlib para evitar dependencia de curl/wget.
- Para Django, substitua o CMD por `gunicorn` com workers adequados.
