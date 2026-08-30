# AGENTS.md — Core Infrastructure Repository

**This is infrastructure-as-code for a self-hosted server (`core.cmnw`), not application source code.** There are no tests, no linting, and no build step. All changes are validated with `docker compose -f compose.<stack>.yaml config` and applied with `up -d`.

---

## Architecture

### Reverse Proxy — Nginx (not Traefik)

Nginx handles all SSL termination and reverse proxying via `compose.routing.yaml`. **Nginx-UI** (`cmnw-nginx-ui`) manages the nginx config through a shared `nginx-config` volume — the UI writes, nginx reads as `:ro`. The host directory `nginx/` contains reference configs but the running container loads from the volume mounted at `/mnt/nginx` on the host.

Domains: `cmnw.me`, `cmnw.xyz`, `cmnw.ru` — each has its own SSL cert in `/etc/nginx/.certs/` inside the container (`/nginx/.certs/` on host, gitignored).

GitLab SSH is proxied through nginx `stream` block on port `2222` → `gitlab:22`.

### Certificate automation — Selectel Certificate Manager

`cmnw.ru`'s TLS cert (wildcard `*.cmnw.ru` + apex) is issued and auto-renewed by **Selectel Certificate Manager** (Let's Encrypt; DNS-01 validation runs automatically because the `cmnw.ru` zone is hosted on Selectel DNS and the domain is delegated to `a/b/c/d.ns.selectel.ru`). Deploying renewals onto nginx is manual for now: download from the panel (Продукты → Менеджер сертификатов → сертификат `cmnw`), write the files to the shared `nginx-config` volume — `/mnt/nginx/.certs/cmnw.ru.{pem,key}` on the host = `/etc/nginx/.certs/` in the nginx container (key `chmod 600`) — then `docker exec cmnw-nginx nginx -t && docker exec cmnw-nginx nginx -s reload`. The download is also scriptable via the panel API (`x-auth-token` auth): `GET https://cloud.api.selcloud.ru/certificate-manager/v1/cert/{cert_id}/ca_chain` and `.../private_key`, where `cert_id` is the knox id shown in the certificate's UID field. Current cert expires 2026-11-19. `cmnw.me` / `cmnw.xyz` are unaffected — they keep using nginx-ui's own ACME.

The former `cert-sync` sidecar (which pulled the cert from Yandex Cloud Certificate Manager nightly) and its GHCR build workflow were removed when the domain moved to Selectel.

### Shared External Network: `cmnw`

Multiple stacks join a pre-created external network named `cmnw` so services can reach each other across compose files. If this network doesn't exist yet, create it: `docker network create cmnw`.

The `traefik` external network referenced by `compose.home.yaml` (node-red labels) and `compose.control.yaml` (portainer) is a legacy remnant — no Traefik stack exists in this repo. These services will fail to start if that network doesn't exist; create it if needed or remove the references.

### Volume Bind Mounts

Several named volumes bind-mount to host paths under `/mnt/`:

| Volume | Host Path | Stack |
|--------|-----------|-------|
| `postgres` | `/mnt/postgres` | storage |
| `rabbitmq` | `/mnt/rabbitmq` | storage |
| `pgvector` | `/mnt/pgvector` | storage |
| `nginx-config` | `/mnt/nginx` | routing |
| `nginx-logs` | `/mnt/nginx/logs` | routing |
| `nginx-ui-state` | `/mnt/nginx-ui` | routing |
| `loki` | `/mnt/loki` | analytics |

These host directories must exist before `up -d` or the volume will fail to mount. Create any missing ones before first deploy:

```bash
sudo mkdir -p /mnt/pgvector
```

### Prometheus Config — Dual Source

`compose.analytics.yaml` embeds prometheus config inline via Docker `configs:` block. The file at `prometheus/prometheus.yml` is **not** used by the running stack — it's a standalone reference. When adding scrape targets, edit the inline `prometheus_config` config block in `compose.analytics.yaml`.

Scrape targets use host IP `128.0.0.255` to reach services that run on the host network (Home Assistant) or on different compose networks.

### Loki — 30-day retention, repo-managed config

Loki does **not** use the image's stock `local-config.yaml`. Like Prometheus, its config is embedded **inline** in `compose.analytics.yaml` (the `loki_config` `configs:` block) — a `file:`-based source does not work here because Portainer runs compose inside its own container and the daemon rejects the resulting bind path. The file at `loki/loki-config.yaml` is the standalone reference copy; edit both together. Retention policy: **30 days, uniform** — enforced by the compactor (`retention_enabled: true`, `retention_period: 30d`) with `max_query_lookback: 30d` capping query windows. Deletion of already-ingested chunks lags by `retention_delete_delay` (default 2h) after the compactor marks them.

Data lives in the `loki` named volume (bind-mounted at `/mnt/loki`, owned by uid 10001 — the image's `loki` user). Historically the container ran with no volume and no retention, accumulating ~14.6 GB in its writable layer; that data was migrated to `/mnt/loki` and retention enabled on 2026-08-19.

### LightRAG — Graph-RAG in the oraculum stack (no Ollama)

`lightrag` in `compose.oraculum.yaml` is the [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG) server. It sits on the `oraculum` bridge network and reaches the storage stack over the host LAN IP `128.0.0.255`:

| LightRAG role | Engine | Service |
|---|---|---|
| Graph storage | PostgreSQL (`PGTableGraphStorage`, no AGE) | `pgvector` (storage stack, `128.0.0.255:5433`, `lightrag` DB) |
| Vector storage | PostgreSQL + pgvector | `pgvector` (same instance and DB) |
| KV + Doc-status | PostgreSQL | `pgvector` (same instance and DB) |

**Image — private fork, GHCR is storage only.** `ghcr.io/alexzedim/lightrag:latest` is a mirror fork of `gitlab.cmnw.ru/sigma/lightrag` (sigma wrapper app + vendored LightRAG engine; ADRs in `docs/adr/` of the fork). The source never lives on GitHub; the image is built and pushed to GHCR manually. Container listens on **8084** (hardcoded), host port stays 9621 via `:8084` mapping. The app has **no built-in auth** — the published port is LAN-only (`128.0.0.255`), keep it that way. API: `POST /create` → `POST /process` → `POST /track`, queries via `POST /read` (scope-based, multi-workspace, 429+`Retry-After` on GPU saturation). Workspaces are per-request (`workspace_id`), one worker per workspace, names lowercased.

**Config comes from the stack env, not the compose file.** All LightRAG vars are injected in their native names (`LLM_MODEL`/`QUERY_LLM_MODEL`/`LLM_BINDING_HOST`, `EMBEDDING_MODEL`, `EMBEDDING_DIM`, `RERANK_*`, `LIGHTRAG_GRAPH_STORAGE`, HNSW/tuning) via `env_file: stack.env`. The source of truth is `../envs/oraculum/.stack.env` — keep the Portainer stack env in sync with it on deploy, Portainer keeps its own copy. Only the `POSTGRES_HOST/PORT/USER/PASSWORD/DATABASE` overrides stay in the compose: those names clash with the shared `POSTGRES_*` block that the oraculum Node apps consume from the same stack env. KV/vector/doc-status storages are hardcoded to the PG backends in the fork — no env selects them. The container is stateless (no volume): graph, vectors, KV and doc-status all live in postgres.

**Dedicated pgvector instance:** the `pgvector` service (image `pgvector/pgvector:0.8.6-pg17`, data at `/mnt/pgvector`) is separate from the shared `postgres` (vanilla `postgres:17.4` on :5432, untouched by LightRAG). The `lightrag` database and its user are created on first init from `LIGHTRAG_PG_*` in the storage stack env (`../envs/storage/.stack.env`) — keep those credentials identical in both stack envs. Vector index uses HNSW with cosine distance. Qdrant and neo4j are gone from the repo entirely; the LightRAG fork now stores its graph in postgres via `PGTableGraphStorage`.

**Loki log shipping — built into the fork, enabled in `../envs/oraculum/.stack.env`.** The fork ships a custom `LokiHandler` (`src/utils/loki_handler.py`) that batches Python `logging` records and POSTs them to `${LOKI_ENDPOINT}/loki/api/v1/push` with retry/backoff. It attaches to both `logging.root` (sigma app logs) and `logging.getLogger("lightrag")` (in-repo engine logs) — so entity extraction, KG merging, RAG queries and the API surface all land in Loki as one stream with `app=lightrag`, `env=prod` labels plus per-request `user_id` / `workspace_id` context. The fork's `gunicorn_conf.py` already gates the handler + the hourly `MetricsService` to worker 0 only, so multi-worker gunicorn deploys don't double-ship. Reachability: lightrag hits Loki via `http://128.0.0.255:3100` (host LAN IP → analytics stack's published port). No compose change needed.

**WebUI — vendored upstream SPA, served at `/webui/` on the same port.** The fork's classic `Dockerfile` (`D:\Projects\ai-platform\lightrag`) runs a multi-stage build that compiles `lightrag_webui/` (Vite + Bun) into `lightrag/api/webui/` and `src/app/main.py` mounts it via a `SmartStaticFiles` subclass that injects `window.__LIGHTRAG_CONFIG__ = {apiPrefix, webuiPrefix}` into `index.html` (same mechanism the upstream `lightrag.api.lightrag_server` uses). Root `/` redirects to `/webui/`. Reachable at `http://128.0.0.255:9621/webui/` from the LAN. Branding via `WEBUI_TITLE` / `WEBUI_DESCRIPTION` in the stack env.

**Upstream-compat routes** in `src/api/webui_routes.py` re-expose the upstream LightRAG HTTP surface the SPA expects (`/documents`, `/documents/upload`, `/documents/text`, `/documents/texts`, `/documents/track_status/{id}`, `/documents/paginated`, `/documents/status_counts`, `/documents/scan`, `/documents/reprocess_failed`, `/documents/cancel_pipeline`, `/documents/pipeline_status`, `/documents/clear_cache`, `/documents/delete_document`, `/documents/supported_file_types`, `/query`, `/query/stream`, `/auth-status`, `/login`, `/graph/entity/{exists,edit}`, `/graph/relation/edit`) and delegate to the fork's existing `/create`, `/process`, `/track`, `/read`, `/delete`, `/clear_cache` services. The SPA is single-tenant: `WEBUI_WORKSPACE` (default `default`) selects the fork workspace it operates against — other workspaces remain reachable via the fork's native API. Caveats: `graph/entity/{exists,edit}` and `graph/relation/edit` return 501 (PGTableGraphStorage does not implement per-entity mutation), `/documents/scan` returns 501 (fork has no INPUT_DIR scanner — upload via the SPA instead), `/login` verifies credentials when `AUTH_ACCOUNTS` is set (see Auth below).

**Auth — upstream-style JWT + API key, enabled via the stack env.** The fork mirrors upstream LightRAG auth (`src/api/auth.py`, reusing the vendored engine's `AuthHandler` and login rate limiter). `AUTH_ACCOUNTS` (comma-separated `user:password`, plaintext or `{bcrypt}`hash) turns on password login for the WebUI — 48 h HS256 JWTs signed with `TOKEN_SECRET`, auto-renewed via `X-New-Token`, 5 failed logins per IP+username per 5 min → 429 — and protects the whole API surface (SPA + native endpoints + `/workspaces`); the whitelist is `/login,/auth-status,/health,/docs,/redoc,/openapi.json`. Service-to-service callers authenticate with `LIGHTRAG_API_KEY` sent as `X-API-Key`: indexator reads it from the same stack env (`lightragConfig.apiKey`) and attaches it on `/create` and `/process` (v1.1.8+). With no `AUTH_ACCOUNTS` the fork runs open and hands out unsigned guest tokens. `AUTH_ACCOUNTS` without a non-default `TOKEN_SECRET` refuses to boot.

**Inference — all via OpenRouter, no local models:**
- **LLMs** — `LLM_MODEL` (extract, `deepseek/deepseek-v4-flash`) and `QUERY_LLM_MODEL` (answers, `deepseek/deepseek-v4-flash`) against `LLM_BINDING_HOST` (OpenRouter). Single model — text-only, 1M ctx, bounded reasoning overhead (~150 tokens), dodges the fork's broken reasoning-disable path on OpenRouter.
- **Embeddings** — `EMBEDDING_MODEL=qwen/qwen3-embedding-0.6b` via OpenRouter ($0.01/M tokens, 1024 dims, 32k context). Switched from `baai/bge-m3` because enriched Discord documents (message + author + channel + parent-context metadata) hit the 8k ceiling with HTTP 400 from bge-m3; qwen3-embedding-0.6b is the same price and same 1024-dim output, so no DB schema or vector-index rebuild needed beyond re-embedding the corpus. `EMBEDDING_DIM=1024` must match.
- **Rerank** — `RERANK_MODEL=cohere/rerank-4-fast` via `RERANK_BINDING_HOST` (OpenRouter).
- No Ollama, no HuggingFace downloads, no GPU — everything is API-routed.

---

## CI/CD Image Flow — local-first deploys

The GitHub Actions runners (`compose.git.yaml`) run on this same host and mount `/var/run/docker.sock`, so every `ghcr.io/alexzedim/*` image they build lands directly in the host Docker daemon **before** it is pushed to GHCR. GHCR is the backup/source of truth; deploys should use the local copy.

- `compose.oracle.yaml` and `compose.oraculum.yaml` set `pull_policy: if_not_present` on all `ghcr.io/alexzedim/*` services: deploy uses the local image and pulls from GHCR only if it's somehow missing locally. Without this, compose's default policy re-pulls `:latest` from GHCR on every deploy. Third-party images (lightrag etc.) keep the default policy.
- Portainer is **CE (2.33.x LTS)**: the stack-webhook `pullimage` parameter and the "Re-pull image" GitOps toggle are Business Edition features and do nothing here. No stack uses GitOps webhooks/polling — deploys are manual ("Pull and redeploy" / "Update the stack"), which runs a plain `docker compose up -d`, so the file-level `pull_policy` is always in effect. Never check a "Re-pull image" option when you want the local copy.
- Quick health check: in Portainer's stack containers table, an image shown as a bare `sha256:…` fragment means the container was created from a registry pull; the image tag means it was created from the local build.
- `docker-prune` (in `compose.git.yaml`) is a nightly janitor (04:30 MSK, `DOCKER_PRUNE_CRON`) that prunes stopped containers, unused images, and build cache older than `DOCKER_PRUNE_RETENTION` (default `48h`). Images used by any container are never removed; volumes are never pruned. Logs: `docker logs docker-prune`.

---

## Stacks

| File | Services | Networks |
|------|----------|----------|
| `compose.storage.yaml` | PostgreSQL 17.4 (vanilla), Redis 7.4.3, MinIO, RabbitMQ 4.2.2, RabbitScout, pgvector 0.8.6 (LightRAG DB, :5433) | `storage-network`, `cmnw` |
| `compose.routing.yaml` | Nginx, Nginx-UI, Nginx Prometheus Exporter | `edge`, `cmnw` |
| `compose.analytics.yaml` | Prometheus, Grafana, Loki, Promtail, Postgres Exporter | `loki`, `cmnw` |
| `compose.home.yaml` | Home Assistant, Mosquitto, Node-RED, Zigbee2MQTT, Z-Wave JS UI, InfluxDB | `traefik` (ext) |
| `compose.git.yaml` | 5× GitHub Actions runners (3× cmnw, 2× oraculum), docker-prune janitor | `runner-network` |
| `compose.gitlab.yaml` | GitLab CE | `cmnw` |
| `compose.oracle.yaml` | 4× vpn-oracle (AdGuard VPN gateways) + oracle / oracle-1d / oracle-2bd / oracle-3s | `oraculum`, `cmnw` (ext) |
| `compose.oraculum.yaml` | indexator, oracular, archivum, gateway, lightrag | `oraculum` |
| `compose.ai.yaml` | GitHub MCP, Grafana MCP | `cmnw` |
| `compose.control.yaml` | Portainer | `traefik` (ext) |
| `compose.ai-local.yaml` | Ollama + Open WebUI with NVIDIA GPU passthrough | `ai-local-network` |

---

## Key Conventions

- **File naming:** `compose.<category>.yaml`
- **Top of each file:** `name: '<category>'` + `version: '3.8'` (some files are missing the version field — add it when editing)
- **4-space indentation** in all YAML
- **Ports:** quote as strings (`'5432:5432'`), except where the existing file already uses unquoted — be consistent within each file
- **Env vars:** use `${VAR_NAME}` in compose files. The committed **`.env.example`** is the canonical template listing every variable the stacks reference — non-secret defaults filled in, secrets blanked. Copy it to `.env` per host and fill in real values. The root `.env` is gitignored (see `.gitignore`: `!/.env` then `.env` — the later pattern wins, so `.env` is ignored while `.env.example` is committed). On the production server, secrets are injected via Portainer env or `stack.env` (`env_file`), never committed. When adding a new `${VAR}` to a compose file, add it to `.env.example` in the matching section.
- **Image tags:** pin specific versions (e.g., `postgres:17.4`), never `:latest` for production services
- **`kebab-case`** for all resource names (networks, volumes, services)
- **`restart: always`** for infrastructure, `unless-stopped` for discretionary services
- **`container_name:`** on every service to avoid auto-generated names

### Intentional Exceptions

- **Home Assistant:** `network_mode: host` + `privileged: true` — required for hardware device discovery and integrations
- **Nginx-UI:** mounts `/var/run/docker.sock` — needed for container discovery
- **Portainer:** mounts `/var/run/docker.sock` — needed for Docker management
- **GitHub Runners:** mount `/var/run/docker.sock` — Docker-in-Docker builds
- **ai-local:** `deploy.resources.reservations.devices` for NVIDIA GPU passthrough
- **gateway (oraculum):** `network_mode: host` — api.adguard.com is IPv4-null-routed on core and only reachable over the host's IPv6

---

## Operational Commands

```bash
# Validate a stack (always do this before up)
docker compose -f compose.<stack>.yaml config

# Start / restart / stop
docker compose -f compose.<stack>.yaml up -d
docker compose -f compose.<stack>.yaml restart <service>
docker compose -f compose.<stack>.yaml down

# Logs
docker compose -f compose.<stack>.yaml logs -f <service>

# Health check
docker exec postgres pg_isready -U postgres

# Backup PostgreSQL
docker exec postgres pg_dump -U postgres cmnw > backup_$(date +%Y%m%d).sql

# Reload nginx after config change (config is shared volume)
docker exec cmnw-nginx nginx -s reload
```

---

## Adding a New Service

1. Add to an existing `compose.<category>.yaml` or create a new one
2. Add env vars to **`.env.example`** (committed template) with a section header (`# ==== Section ====`) — non-secret defaults filled, secrets blank. Then copy the new vars into your local `.env` with real values.
3. For cross-stack connectivity, join the `cmnw` external network
4. For persistent data, add a named volume (use bind mount to `/mnt/<name>` if the data needs a known host path)
5. If the service should be reachable via HTTPS, add a server block in the appropriate `nginx/conf.d/*.conf` file
6. Validate: `docker compose -f compose.<category>.yaml config`
7. Deploy: `docker compose -f compose.<category>.yaml up -d`
