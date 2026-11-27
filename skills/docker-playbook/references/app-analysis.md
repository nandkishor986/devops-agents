# Study the application before writing a Dockerfile

Read only what answers these questions (manifest files, a README section, the entrypoint) — don't read the whole codebase.

| Question | Where to look |
|---|---|
| Language + version | `package.json` engines / `.nvmrc`, `pyproject.toml` / `.python-version`, `go.mod`, `pom.xml` / `build.gradle`, `*.csproj` `TargetFramework`, `Gemfile`, `composer.json` |
| Package manager + lockfile | `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock`, `poetry.lock` / `uv.lock` / `requirements.txt`, `go.sum`, Maven/Gradle wrapper |
| Build command + output | scripts `build`, `mvn package`, `go build`, `dotnet publish -c Release -o out` |
| Start command | scripts `start`, `Procfile`, `main` / `__main__`, ASGI/WSGI app (`uvicorn app:app`, `gunicorn`), jar name |
| Port | code/env (`PORT`, `server.port`, `app.listen`), existing manifests/compose |
| Health endpoint | `/health`, `/healthz`, `/actuator/health`, `/ready` — or add a lightweight one with the user's OK |
| Config & secrets | `.env.example`, settings files → env vars at runtime, never baked into the image |
| Native/system deps | `node-gyp`, `psycopg2` vs `psycopg2-binary`, `libc` needs, fonts/ImageMagick |
| Static assets / frontend | SPA build → serve from nginx-unprivileged or the backend |

## Then choose the base and shape
| Stack | Build stage | Runtime stage |
|---|---|---|
| Node | `node:<lts>-slim` with `npm ci` | `node:<lts>-slim` (or distroless nodejs), `USER node` |
| Python | `python:<ver>-slim` + venv / `uv` | same slim, copy venv, non-root user |
| Go | `golang:<ver>` `CGO_ENABLED=0` | `gcr.io/distroless/static:nonroot` |
| Java | `maven`/`gradle` JDK | `eclipse-temurin:<ver>-jre` or distroless java |
| .NET | `mcr.microsoft.com/dotnet/sdk` | `mcr.microsoft.com/dotnet/aspnet` (chiseled when possible), `USER app` |

Always: multi-stage, dependency layer before source (cache), pinned base (tag + digest for prod), non-root, `HEALTHCHECK` matching the real port/endpoint, `.dockerignore` (`.git`, `node_modules`, `.env*`, tests, local build output). Then `docker-verify.sh` until healthy.
