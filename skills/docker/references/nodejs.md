# Dockerfile — Node.js

Exemplo completo de Dockerfile multi-stage para aplicacoes Node.js com imagem final Alpine.

```dockerfile
FROM node:22.14-alpine3.21 AS builder

WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts

COPY . .
RUN npm run build && npm prune --production

FROM node:22.14-alpine3.21 AS runtime

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/package.json ./

USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/health"]
CMD ["node", "dist/server.js"]
```

## Notas

- Use `npm ci` em vez de `npm install` para builds reproduziveis.
- `--ignore-scripts` evita execucao de scripts pos-instalacao no estagio de build.
- `npm prune --production` remove devDependencies antes de copiar para o runtime.
- Alpine ja inclui `wget` para healthcheck.
- Para Next.js, considere usar o output `standalone` para imagens menores.
