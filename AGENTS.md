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
| `qdrant` | `/mnt/qdrant` | storage |
| `neo4j` | `/mnt/neo4j` | storage |
| `nginx-config` | `/mnt/nginx` | routing |
| `nginx-logs` | `/mnt/nginx/logs` | routing |
| `nginx-ui-state` | `/mnt/nginx-ui` | routing |
| `ollama` | `/mnt/ollama` | ai |
| `lightrag-data` | `/mnt/lightrag` | ai |

These host directories must exist before `up -d` or the volume will fail to mount. Create any missing ones before first deploy:

```bash
sudo mkdir -p /mnt/neo4j /mnt/lightrag
sudo chown -R 7474:7474 /mnt/neo4j   # Neo4j runs as uid 7474; will refuse to start otherwise
```

### Prometheus Config — Dual Source

`docker-compose.analytics.yml` embeds prometheus config inline via Docker `configs:` block. The file at `prometheus/prometheus.yml` is **not** used by the running stack — it's a standalone reference. When adding scrape targets, edit the inline `prometheus_config` config block in `docker-compose.analytics.yml`.

Scrape targets use host IP `128.0.0.255` to reach services that run on the host network (Home Assistant) or on different compose networks.

### LightRAG — Graph-RAG (no Ollama)

`lightrag` in `docker-compose.ai.yml` is the [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG) server. It reuses existing storage services over the `cmnw` network instead of bringing its own:

| LightRAG role | Engine | Service |
|---|---|---|
| Graph storage | Neo4j | `neo4j` (from `storage.yml`) |
| Vector storage | PostgreSQL + pgvector | `postgres` (from `storage.yml`, `POSTGRES_LIGHTRAG_DB` database) |
| KV + Doc-status | PostgreSQL | `postgres` (from `storage.yml`, `POSTGRES_LIGHTRAG_DB` database) |

**Inference — all via OpenRouter, no local models:**
- **LLMs** — OpenAI-compatible binding (`LLM_BINDING=openai` + `OPENROUTER_BASE_URL`). Role routing: `LIGHTRAG_LLM_MODEL` (extract), `LIGHTRAG_KEYWORD_LLM_MODEL`, `LIGHTRAG_QUERY_LLM_MODEL`.
- **Embeddings** — `EMBEDDING_BINDING=openai` → `baai/bge-m3` ($0.01/M tokens, 1024 dims, strong multilingual/Russian per ruMTEB).
- **Rerank** — `RERANK_BINDING=cohere` → `cohere/rerank-4-fast` ($0.002/search, 100+ languages). Set `RERANK_BINDING: null` to disable.
- No Ollama, no HuggingFace downloads, no GPU — everything is API-routed.

**Postgres + pgvector (hybrid storage):** KV, doc-status, and vector storage all run on the existing Postgres container, which uses the `pgvector/pgvector:0.8.0-pg17` image (official postgres:17 with the pgvector extension pre-compiled — drop-in compatible with the data dir at `/mnt/postgres`). LightRAG's tables live in a dedicated `lightrag` database (set via `POSTGRES_LIGHTRAG_DB`), auto-created by `postgres/init/10-create-lightrag-db.sql` on first Postgres initialization. LightRAG auto-runs `CREATE EXTENSION IF NOT EXISTS vector` on first connect, so no manual extension setup is needed. Vector index uses HNSW with cosine distance (`POSTGRES_VECTOR_INDEX_TYPE=hnsw_cosine`). Qdrant remains in `storage.yml` for other apps but LightRAG no longer uses it.

**Prerequisite:** if Postgres has already been initialized (data dir exists at `/mnt/postgres`), the init script will NOT run — create the `lightrag` database manually instead:
```bash
docker exec postgres psql -U postgres -c "CREATE DATABASE lightrag;"
```

---

## Stacks

| File | Services | Networks |
|------|----------|----------|
| `docker-compose.storage.yml` | PostgreSQL 17.4, Redis 7.4.3, MinIO, RabbitMQ 4.2.2, Qdrant, Neo4j | `storage-network` |
| `docker-compose.routing.yml` | Nginx, Nginx-UI, Nginx Prometheus Exporter, cert-sync | `edge`, `cmnw` |
| `docker-compose.analytics.yml` | Prometheus, Grafana, Loki, Promtail, Postgres Exporter | `loki`, `cmnw` |
| `docker-compose.home.yml` | Home Assistant, Mosquitto, Node-RED, Zigbee2MQTT, Z-Wave JS UI, InfluxDB | `traefik` (ext) |
| `docker-compose.git.yml` | 5× GitHub Actions runners (3× cmnw, 2× oraculum) | `runner-network` |
| `docker-compose.gitlab.yml` | GitLab CE | `cmnw` |
| `docker-compose.ai.yml` | LightRAG, Neo4j, Open WebUI, Qdrant, GitHub MCP, Grafana MCP | `cmnw` |
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
