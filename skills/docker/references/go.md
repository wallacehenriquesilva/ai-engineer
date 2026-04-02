# Dockerfile — Go

Exemplo completo de Dockerfile multi-stage para serviços Go com imagem final `distroless/static`.

```dockerfile
ARG GO_VERSION=1.24
FROM golang:${GO_VERSION}-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app ./cmd/server

FROM gcr.io/distroless/static-debian12
USER nonroot:nonroot
COPY --from=builder /app /app

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
```

## Notas

- Use `scratch` ou `distroless/static` como imagem final quando CGO esta desabilitado.
- `-ldflags="-s -w"` remove simbolos de debug e reduz o tamanho do binario.
- O usuario `nonroot` ja existe na imagem distroless.
- O healthcheck deve ser implementado no proprio binario, pois distroless nao tem curl/wget.
- Para servicos com `ca-starters-go`, o graceful shutdown ja esta implementado no framework.
