# AGENTS.md — Core Infrastructure Repository

**This is infrastructure-as-code for a self-hosted server (`core.cmnw`), not application source code.** There are no tests, no linting, and no build step. All changes are validated with `docker-compose -f docker-compose.<stack>.yml config` and applied with `up -d`.

---

## Architecture

### Reverse Proxy — Nginx (not Traefik)

Nginx handles all SSL termination and reverse proxying via `docker-compose.routing.yml`. **Nginx-UI** (`cmnw-nginx-ui`) manages the nginx config through a shared `nginx-config` volume — the UI writes, nginx reads as `:ro`. The host directory `nginx/` contains reference configs but the running container loads from the volume mounted at `/mnt/nginx` on the host.

Domains: `cmnw.me`, `cmnw.xyz`, `cmnw.ru` — each has its own SSL cert in `/etc/nginx/.certs/` inside the container (`/nginx/.certs/` on host, gitignored).

GitLab SSH is proxied through nginx `stream` block on port `2222` → `gitlab:22`.

### Certificate automation — cert-sync

`cmnw.ru`'s TLS cert is issued by **Yandex Cloud Certificate Manager** (Let's Encrypt, auto-renewed on YC's side). The **cert-sync** sidecar (`docker-compose.routing.yml`) bridges those renewals onto the self-hosted nginx: nightly at 03:15 MSK (and once on startup) it pulls the chain + key via `yc certificate-manager certificate content`, validates them, and reloads nginx only when they changed. `cmnw.me` / `cmnw.xyz` are unaffected — they keep using nginx-ui's own ACME.

The sidecar writes into the shared `nginx-config` volume (`/certs/.certs/` inside the container = `/mnt/nginx/.certs` on the host = `/etc/nginx/.certs` in nginx), so no nginx config changes were needed. It reloads nginx via the Docker socket (`docker exec cmnw-nginx nginx -s reload`).

**Credentials:** the YC service-account key (role `certificate-manager.certificates.downloader`) is provided via `YC_AUTHORIZED_KEY` (full `authorized_key.json` contents — set in Portainer env / `.env`), or alternatively bind-mounted at `/secrets/authorized_key.json`. The cert ID lives in `YC_CERT_ID`. See `cert-sync/README.md` for one-time setup.

### Shared External Network: `cmnw`

Multiple stacks join a pre-created external network named `cmnw` so services can reach each other across compose files. If this network doesn't exist yet, create it: `docker network create cmnw`.

The `traefik` external network referenced by `docker-compose.home.yml` (node-red labels) and `docker-compose.control.yml` (portainer) is a legacy remnant — no Traefik stack exists in this repo. These services will fail to start if that network doesn't exist; create it if needed or remove the references.

### Volume Bind Mounts

Several named volumes bind-mount to host paths under `/mnt/`:

| Volume | Host Path | Stack |
|--------|-----------|-------|
| `postgres` | `/mnt/postgres` | storage |
| `rabbitmq` | `/mnt/rabbitmq` | storage |
| `pgvector` | `/mnt/pgvector` | storage |
| `neo4j` | `/mnt/neo4j` | storage |
| `nginx-config` | `/mnt/nginx` | routing |
| `nginx-logs` | `/mnt/nginx/logs` | routing |
| `nginx-ui-state` | `/mnt/nginx-ui` | routing |
| `lightrag-data` | `/mnt/lightrag` | oraculum |
| `loki` | `/mnt/loki` | analytics |

These host directories must exist before `up -d` or the volume will fail to mount. Create any missing ones before first deploy:

```bash
sudo mkdir -p /mnt/neo4j /mnt/pgvector /mnt/lightrag
sudo chown -R 7474:7474 /mnt/neo4j   # Neo4j runs as uid 7474; will refuse to start otherwise
```

### Prometheus Config — Dual Source

`docker-compose.analytics.yml` embeds prometheus config inline via Docker `configs:` block. The file at `prometheus/prometheus.yml` is **not** used by the running stack — it's a standalone reference. When adding scrape targets, edit the inline `prometheus_config` config block in `docker-compose.analytics.yml`.

Scrape targets use host IP `128.0.0.255` to reach services that run on the host network (Home Assistant) or on different compose networks.

### Loki — 30-day retention, repo-managed config

Loki does **not** use the image's stock `local-config.yaml`. Like Prometheus, its config is embedded **inline** in `docker-compose.analytics.yml` (the `loki_config` `configs:` block) — a `file:`-based source does not work here because Portainer runs compose inside its own container and the daemon rejects the resulting bind path. The file at `loki/loki-config.yaml` is the standalone reference copy; edit both together. Retention policy: **30 days, uniform** — enforced by the compactor (`retention_enabled: true`, `retention_period: 30d`) with `max_query_lookback: 30d` capping query windows. Deletion of already-ingested chunks lags by `retention_delete_delay` (default 2h) after the compactor marks them.

Data lives in the `loki` named volume (bind-mounted at `/mnt/loki`, owned by uid 10001 — the image's `loki` user). Historically the container ran with no volume and no retention, accumulating ~14.6 GB in its writable layer; that data was migrated to `/mnt/loki` and retention enabled on 2026-08-19.

### LightRAG — Graph-RAG in the oraculum stack (no Ollama)

`lightrag` in `docker-compose.oraculum.yml` is the [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG) server. It sits on the `oraculum` bridge network and reaches the storage stack over the host LAN IP `128.0.0.255`:

| LightRAG role | Engine | Service |
|---|---|---|
| Graph storage | Neo4j | `neo4j` (storage stack, `bolt://128.0.0.255:7687`) |
| Vector storage | PostgreSQL + pgvector | `pgvector` (storage stack, `128.0.0.255:5433`, `lightrag` DB) |
| KV + Doc-status | PostgreSQL | `pgvector` (same instance and DB) |

**Config comes from the stack env, not the compose file.** All LightRAG vars are injected in their native names (`LLM_BINDING*`, `KEYWORD/QUERY_LLM_*`, `EMBEDDING_*`, `RERANK_*`, `NEO4J_*`, storage-engine selection, HNSW/tuning) via `env_file: stack.env`. The source of truth is `../envs/oraculum/.stack.env` — keep the Portainer stack env in sync with it on deploy, Portainer keeps its own copy. Only `HOST`, `PORT`, `TOKEN_SECRET` and the `POSTGRES_PORT/USER/PASSWORD` overrides stay in the compose: those names clash with the shared `POSTGRES_*` block that the oraculum Node apps consume from the same stack env.

**Dedicated pgvector instance:** the `pgvector` service (image `pgvector/pgvector:0.8.6-pg17`, data at `/mnt/pgvector`) is separate from the shared `postgres` (vanilla `postgres:17.4` on :5432, untouched by LightRAG). The `lightrag` database and its user are created on first init from `LIGHTRAG_PG_*` in the storage stack env (`../envs/storage/.stack.env`) — keep those credentials identical in both stack envs. Vector index uses HNSW with cosine distance. Qdrant is gone from the repo entirely.

**Inference — all via OpenRouter, no local models:**
- **LLMs** — OpenAI-compatible binding (`LLM_BINDING=openai` + OpenRouter host). Role routing: `LLM_MODEL` (extract), `KEYWORD_LLM_MODEL`, `QUERY_LLM_MODEL`.
- **Embeddings** — `EMBEDDING_BINDING=openai` → `baai/bge-m3` ($0.01/M tokens, 1024 dims, strong multilingual/Russian per ruMTEB).
- **Rerank** — `RERANK_BINDING=cohere` → `cohere/rerank-4-fast` ($0.002/search, 100+ languages). Set `RERANK_BINDING` empty to disable.
- No Ollama, no HuggingFace downloads, no GPU — everything is API-routed.

---

## CI/CD Image Flow — local-first deploys

The GitHub Actions runners (`docker-compose.git.yml`) run on this same host and mount `/var/run/docker.sock`, so every `ghcr.io/alexzedim/*` image they build lands directly in the host Docker daemon **before** it is pushed to GHCR. GHCR is the backup/source of truth; deploys should use the local copy.

- `docker-compose.oracle.yml` and `docker-compose.oraculum.yml` set `pull_policy: if_not_present` on all `ghcr.io/alexzedim/*` services: deploy uses the local image and pulls from GHCR only if it's somehow missing locally. Without this, compose's default policy re-pulls `:latest` from GHCR on every deploy. Third-party images (lightrag etc.) keep the default policy.
- Portainer is **CE (2.33.x LTS)**: the stack-webhook `pullimage` parameter and the "Re-pull image" GitOps toggle are Business Edition features and do nothing here. No stack uses GitOps webhooks/polling — deploys are manual ("Pull and redeploy" / "Update the stack"), which runs a plain `docker compose up -d`, so the file-level `pull_policy` is always in effect. Never check a "Re-pull image" option when you want the local copy.
- Quick health check: in Portainer's stack containers table, an image shown as a bare `sha256:…` fragment means the container was created from a registry pull; the image tag means it was created from the local build.
- `docker-prune` (in `docker-compose.git.yml`) is a nightly janitor (04:30 MSK, `DOCKER_PRUNE_CRON`) that prunes stopped containers, unused images, and build cache older than `DOCKER_PRUNE_RETENTION` (default `48h`). Images used by any container are never removed; volumes are never pruned. Logs: `docker logs docker-prune`.

---

## Stacks

| File | Services | Networks |
|------|----------|----------|
| `docker-compose.storage.yml` | PostgreSQL 17.4 (vanilla), Redis 7.4.3, MinIO, RabbitMQ 4.2.2, RabbitScout, pgvector 0.8.6 (LightRAG DB, :5433), Neo4j 5.26 | `storage-network`, `cmnw` |
| `docker-compose.routing.yml` | Nginx, Nginx-UI, Nginx Prometheus Exporter, cert-sync | `edge`, `cmnw` |
| `docker-compose.analytics.yml` | Prometheus, Grafana, Loki, Promtail, Postgres Exporter | `loki`, `cmnw` |
| `docker-compose.home.yml` | Home Assistant, Mosquitto, Node-RED, Zigbee2MQTT, Z-Wave JS UI, InfluxDB | `traefik` (ext) |
| `docker-compose.git.yml` | 5× GitHub Actions runners (3× cmnw, 2× oraculum), docker-prune janitor | `runner-network` |
| `docker-compose.gitlab.yml` | GitLab CE | `cmnw` |
| `docker-compose.oracle.yml` | 4× vpn-oracle (AdGuard VPN gateways) + oracle / oracle-1d / oracle-2bd / oracle-3s | `oraculum`, `cmnw` (ext) |
| `docker-compose.oraculum.yml` | indexator, oracular, archivum, gateway, lightrag | `oraculum` |
| `docker-compose.ai.yml` | GitHub MCP, Grafana MCP, Open WebUI | `cmnw` |
| `docker-compose.control.yml` | Portainer | `traefik` (ext) |
| `docker-compose.ai-local.yml` | Ollama + Open WebUI with NVIDIA GPU passthrough | `ai-local-network` |

---

## Key Conventions

- **File naming:** `docker-compose.<category>.yml`
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
docker-compose -f docker-compose.<stack>.yml config

# Start / restart / stop
docker-compose -f docker-compose.<stack>.yml up -d
docker-compose -f docker-compose.<stack>.yml restart <service>
docker-compose -f docker-compose.<stack>.yml down

# Logs
docker-compose -f docker-compose.<stack>.yml logs -f <service>

# Health check
docker exec postgres pg_isready -U postgres

# Backup PostgreSQL
docker exec postgres pg_dump -U postgres cmnw > backup_$(date +%Y%m%d).sql

# Reload nginx after config change (config is shared volume)
docker exec cmnw-nginx nginx -s reload
```

---

## Adding a New Service

1. Add to an existing `docker-compose.<category>.yml` or create a new one
2. Add env vars to **`.env.example`** (committed template) with a section header (`# ==== Section ====`) — non-secret defaults filled, secrets blank. Then copy the new vars into your local `.env` with real values.
3. For cross-stack connectivity, join the `cmnw` external network
4. For persistent data, add a named volume (use bind mount to `/mnt/<name>` if the data needs a known host path)
5. If the service should be reachable via HTTPS, add a server block in the appropriate `nginx/conf.d/*.conf` file
6. Validate: `docker-compose -f docker-compose.<category>.yml config`
7. Deploy: `docker-compose -f docker-compose.<category>.yml up -d`
