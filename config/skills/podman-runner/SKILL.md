---
name: podman-runner
description: Enforce containerized execution for test runners, builds, and migrations using Podman. Use when running tests (jest, vitest), compiling code, executing database migrations, checking container health, or inspecting container logs to avoid host CPU/RAM exhaustion.
---

# Podman Runner & Containerized Execution Standards

## Use When
- Executing test suites (`jest`, `vitest`, `mocha`, `npm test`, `npm run test-unit`, `pytest`).
- Compiling codebases or running full workspace builds (`ng build`, `nest build`, `tsc`, `mvn package`, `cargo build`).
- Running database migrations or seeders (`typeorm migration:run`, `prisma migrate`, `liquibase`).
- Checking container status, health, readiness, or reviewing container log output.
- Interacting with repositories that provide a `docker-compose.yml`, `compose.yaml`, `Containerfile`, or `Dockerfile`.

## Core Invariants

1. **Zero Bare-Metal Workloads**: NEVER execute intensive build, compilation, test, or migration commands directly on the host machine when a containerized environment (Podman / Docker Compose) is present.
2. **Worker & Concurrency Limits**: ALWAYS restrict test concurrency to avoid host starvation (e.g., `--maxWorkers=2` or `--runInBand` for Jest; `--threads=false` or `--maxConcurrency=2` for Vitest).
3. **Resource-Bounded Execution**: When launching one-off containers via `podman run`, ALWAYS enforce memory and CPU limits (e.g., `--cpus="2"` `--memory="2g"`).
4. **Non-Blocking Output & Log Bounds**: NEVER run infinite log tail commands (`podman compose logs -f` without timeout or bound). ALWAYS use bounded tail options (e.g., `--tail=100`) or specific timestamps.

---

## Execution Recipes

### 1. Service Health & Readiness Checks
Before executing commands against a running container or service, verify state:

```bash
# Check status of compose services
podman compose ps

# Inspect container health status directly
podman inspect --format='{{.State.Health.Status}}' <container_name_or_id> 2>/dev/null || podman inspect --format='{{.State.Status}}' <container_name_or_id>

# Await service readiness with a bounded retry loop (fail-fast, max 30s)
for i in {1..15}; do
  status=$(podman inspect --format='{{.State.Health.Status}}' <container_name> 2>/dev/null || true)
  [[ "$status" == "healthy" ]] && break
  sleep 2
done
```

### 2. Bounded Test Suite Execution
Always execute within the target service container and clamp concurrency:

```bash
# Jest with memory/worker constraints
podman compose exec <service> npm test -- --runInBand --colors=false

# Jest with explicit worker cap
podman compose exec <service> npx jest --maxWorkers=2 --ci

# Vitest inside compose
podman compose exec <service> npx vitest run --maxConcurrency=2

# Python pytest inside compose
podman compose exec <service> pytest -o log_cli=true -n 2
```

### 3. One-Off Isolated Container Runs
When no compose stack is running or for isolated single-command environments:

```bash
# Bounded test run with CPU and memory caps
podman run --rm \
  --cpus=2 \
  --memory=2g \
  -v "$PWD":/app:z \
  -w /app \
  <image_name> \
  npm test -- --maxWorkers=2
```

### 4. Database Migrations & Compilation
Run migrations and builds inside the dedicated runtime container:

```bash
# NestJS / TypeScript build
podman compose exec <service> npm run build

# TypeORM migrations
podman compose exec <service> npm run typeorm:migration:run

# Prisma migrations
podman compose exec <service> npx prisma migrate deploy
```

### 5. Safe Container Log Inspection
Avoid unbounded log streaming that can hang automated sessions:

```bash
# Safe: Fetch recent 100 log lines with timestamps
podman compose logs --tail=100 --timestamps <service>

# Safe: Fetch logs since last 5 minutes
podman compose logs --since=5m <service>

# Inspect specific failure logs for dead containers
podman logs --tail=100 <container_id>
```
