# Dockerfile patterns (load only when writing/optimising)
Replace version tags with current pinned ones (check Docker Hub via MCP or `docker buildx imagetools inspect <image>:<tag>` for the digest).

## Node.js
```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev

FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build

FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app
COPY --from=deps  /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER 65532:65532
EXPOSE 8080
CMD ["dist/server.js"]
```

## Python
```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS build
ENV PIP_NO_CACHE_DIR=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip python -m venv /venv && /venv/bin/pip install -r requirements.txt
COPY . .

FROM python:3.12-slim
RUN useradd -u 10001 -r -s /sbin/nologin app
COPY --from=build /venv /venv
COPY --from=build /app /app
WORKDIR /app
ENV PATH=/venv/bin:$PATH PYTHONUNBUFFERED=1
USER 10001
ENTRYPOINT ["gunicorn", "-b", "0.0.0.0:8080", "app:app"]
```

## Go (static → scratch/distroless)
```dockerfile
# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM golang:1.23 AS build
ARG TARGETOS TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/app
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

## Java (Spring Boot layered)
```dockerfile
# syntax=docker/dockerfile:1
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN --mount=type=cache,target=/root/.m2 ./mvnw -q dependency:go-offline
COPY src src
RUN --mount=type=cache,target=/root/.m2 ./mvnw -q package -DskipTests && \
    java -Djarmode=tools -jar target/*.jar extract --layers --launcher --destination /out
FROM eclipse-temurin:21-jre-alpine
RUN adduser -D -u 10001 app
WORKDIR /app
COPY --from=build /out/dependencies/ ./
COPY --from=build /out/spring-boot-loader/ ./
COPY --from=build /out/snapshot-dependencies/ ./
COPY --from=build /out/application/ ./
USER 10001
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

## .NET
```dockerfile
# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY *.sln ./
COPY src/Api/Api.csproj src/Api/
RUN --mount=type=cache,target=/root/.nuget/packages dotnet restore src/Api/Api.csproj
COPY . .
RUN --mount=type=cache,target=/root/.nuget/packages dotnet publish src/Api/Api.csproj -c Release -o /out --no-restore
FROM mcr.microsoft.com/dotnet/aspnet:8.0-noble-chiseled
WORKDIR /app
COPY --from=build /out .
USER $APP_UID
ENTRYPOINT ["dotnet", "Api.dll"]
```

## .dockerignore baseline
```
.git
.github
.azure-pipelines
**/node_modules
**/bin
**/obj
**/__pycache__
.env*
*.pem
*.pfx
*.key
**/.terraform
Dockerfile*
docker-compose*
```

## BuildKit / buildx essentials
- Multi-arch: `docker buildx build --platform linux/amd64,linux/arm64 -t <acr>/app:1.0 --push .`
- Remote cache in CI: `--cache-from type=registry,ref=<acr>/app:buildcache --cache-to type=registry,ref=<acr>/app:buildcache,mode=max`
- ADO: `Docker@2` task or `az acr build` (no daemon needed on agent); GitHub: `docker/build-push-action` with `cache-from: type=gha`.
- Debug a stage: `docker build --target build -t dbg . && docker run --rm -it dbg sh`
- Context too big / slow: check `.dockerignore`, `docker build --progress=plain 2>&1 | grep 'transferring context'`.

## Compose (dev)
Use `depends_on: { db: { condition: service_healthy } }`, named volumes, `profiles:` for optional services, `develop.watch` for live reload; never put prod secrets in `.env` committed to Git.
