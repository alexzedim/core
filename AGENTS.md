# AGENTS.md — Core Infrastructure Repository

**This is infrastructure-as-code for a self-hosted server (`core.cmnw`), not application source code.** There are no tests, no linting, and no build step. All changes are validated with `docker-compose -f docker-compose.<stack>.yml config` and applied with `up -d`.

---

## Architecture

### Reverse Proxy — Nginx (not Traefik)

Nginx handles all SSL termination and reverse proxying via `docker-compose.routing.yml`. **Nginx-UI** (`cmnw-nginx-ui`) manages the nginx config through a shared `nginx-config` volume — the UI writes, nginx reads as `:ro`. The host directory `nginx/` contains reference configs but the running container loads from the volume mounted at `/mnt/nginx` on the host.

Domains: `cmnw.me`, `cmnw.xyz`, `cmnw.ru` — each has its own SSL cert in `/etc/nginx/.certs/` inside the container (`/nginx/.certs/` on host, gitignored).

GitLab SSH is proxied through nginx `stream` block on port `2222` → `gitlab:22`.

### Shared External Network: `cmnw`

Multiple stacks join a pre-created external network named `cmnw` so services can reach each other across compose files. If this network doesn't exist yet, create it: `docker network create cmnw`.

The `traefik` external network referenced by `docker-compose.home.yml` (node-red labels) and `docker-compose.control.yml` (portainer) is a legacy remnant — no Traefik stack exists in this repo. These services will fail to start if that network doesn't exist; create it if needed or remove the references.

### Volume Bind Mounts

Several named volumes bind-mount to host paths under `/mnt/`:

| Volume | Host Path | Stack |
|--------|-----------|-------|
| `postgres` | `/mnt/postgres` | storage |
| `rabbitmq` | `/mnt/rabbitmq` | storage |
| `nginx-config` | `/mnt/nginx` | routing |
| `nginx-logs` | `/mnt/nginx/logs` | routing |
| `nginx-ui-state` | `/mnt/nginx-ui` | routing |
| `qdrant` | `/mnt/qdrant` | ai |
| `ollama` | `/mnt/ollama` | ai |

These host directories must exist before `up -d` or the volume will fail to mount.

### Prometheus Config — Dual Source

`docker-compose.analytics.yml` embeds prometheus config inline via Docker `configs:` block. The file at `prometheus/prometheus.yml` is **not** used by the running stack — it's a standalone reference. When adding scrape targets, edit the inline `prometheus_config` config block in `docker-compose.analytics.yml`.

Scrape targets use host IP `128.0.0.255` to reach services that run on the host network (Home Assistant) or on different compose networks.

---

## Stacks

| File | Services | Networks |
|------|----------|----------|
| `docker-compose.storage.yml` | PostgreSQL 17.4, Redis 7.4.3, MinIO, RabbitMQ 4.2.2 | `storage-network` |
| `docker-compose.routing.yml` | Nginx, Nginx-UI, Nginx Prometheus Exporter | `edge`, `cmnw` |
| `docker-compose.analytics.yml` | Prometheus, Grafana, Loki, Promtail, Postgres Exporter | `loki`, `cmnw` |
| `docker-compose.home.yml` | Home Assistant, Mosquitto, Node-RED, Zigbee2MQTT, Z-Wave JS UI, InfluxDB | `traefik` (ext) |
| `docker-compose.git.yml` | 5× GitHub Actions runners (3× cmnw, 2× oraculum) | `runner-network` |
| `docker-compose.gitlab.yml` | GitLab CE | `cmnw` |
| `docker-compose.ai.yml` | Ollama, Open WebUI, Qdrant, GitHub MCP, Grafana MCP | `cmnw` |
| `docker-compose.control.yml` | Portainer | `traefik` (ext) |
| `docker-compose.ai-local.yml` | Ollama + Open WebUI with NVIDIA GPU passthrough | `ai-local-network` |

---

## Key Conventions

- **File naming:** `docker-compose.<category>.yml`
- **Top of each file:** `name: '<category>'` + `version: '3.8'` (some files are missing the version field — add it when editing)
- **4-space indentation** in all YAML
- **Ports:** quote as strings (`'5432:5432'`), except where the existing file already uses unquoted — be consistent within each file
- **Env vars:** use `${VAR_NAME}` in compose files. Secrets come from `.env` (gitignored, not committed) or `stack.env` (used by home stack services via `env_file`)
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
2. Add env vars to `.env` with a section header (`# ==== Section ====`)
3. For cross-stack connectivity, join the `cmnw` external network
4. For persistent data, add a named volume (use bind mount to `/mnt/<name>` if the data needs a known host path)
5. If the service should be reachable via HTTPS, add a server block in the appropriate `nginx/conf.d/*.conf` file
6. Validate: `docker-compose -f docker-compose.<category>.yml config`
7. Deploy: `docker-compose -f docker-compose.<category>.yml up -d`
