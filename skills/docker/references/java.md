# Dockerfile — Java (Spring Boot)

Exemplo completo de Dockerfile multi-stage para servicos Java/Spring Boot com layer extraction.

```dockerfile
FROM eclipse-temurin:21-jdk-jammy AS builder

WORKDIR /build

COPY pom.xml mvnw ./
COPY .mvn .mvn
RUN ./mvnw dependency:resolve -B

COPY src ./src
RUN ./mvnw package -DskipTests -B && \
    java -Djarmode=layertools -jar target/*.jar extract --destination /extracted

FROM eclipse-temurin:21-jre-jammy AS runtime

RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app
COPY --from=builder /extracted/dependencies/ ./
COPY --from=builder /extracted/spring-boot-loader/ ./
COPY --from=builder /extracted/snapshot-dependencies/ ./
COPY --from=builder /extracted/application/ ./

USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["java", "-cp", ".", "org.springframework.boot.loader.launch.HealthCheck"]
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

## Notas

- Use `eclipse-temurin` como imagem base — e a distribuicao recomendada do OpenJDK.
- Use JDK no estagio de build e JRE no estagio de runtime.
- O layer extraction do Spring Boot separa dependencias do codigo da aplicacao, otimizando cache.
- `-B` (batch mode) no Maven desabilita output interativo e e recomendado para CI/Docker.
- `start-period` deve ser maior para Java (30s+) devido ao tempo de inicializacao da JVM.
- Para Gradle, substitua os comandos Maven por `./gradlew build -x test`.
