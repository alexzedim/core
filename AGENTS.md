# AGENTS.md — Core Infrastructure Repository

**This is infrastructure-as-code for a self-hosted server (`core.cmnw`), not application source code.** There are no tests, no linting, and no build step. All changes are validated with `docker compose -f compose.<stack>.yaml config` and applied with `up -d`.

---

## Architecture

### Reverse Proxy — Caddy + caddy-proxy-manager

Caddy (`cmnw-caddy`) handles all SSL termination and reverse proxying via `compose.routing.yaml`. **caddy-proxy-manager** ([fuomag9/caddy-proxy-manager](https://github.com/fuomag9/caddy-proxy-manager), web UI at `http://128.0.0.255:3001`, LAN-only — :3000 is grafana) owns the routing config — proxy hosts, location rules, access lists, certificates — in its SQLite DB at `/mnt/caddy-manager` (**include it in host backups — it is the source of truth; there is no Caddyfile on disk**) and pushes generated JSON to Caddy's admin API (`http://cmnw-caddy:2019`, `routing-internal` network) with zero-downtime reloads. Config changes are made in the panel UI, not in this repo. Deploy files live on the server (compose + `stack.env`), outside this repo.

Panel images are **our own patch-build** of upstream ([ingres-si/ingressi](https://github.com/ingres-si/ingressi) — formerly `fuomag9/caddy-proxy-manager`, GitHub redirects the old name; tag-pinned): `.github/workflows/build-caddy-panel.yml` clones the upstream at `UPSTREAM_TAG`, applies `caddy-panel/apply-selectel.cjs` (adds `caddy-dns/selectel` to the xcaddy build + the panel provider registry, and sets builder `GOPROXY=goproxy.cn,direct` — the runner's IPv4-only docker bridge gets connection-reset from Google's module-zip store) and pushes `ghcr.io/alexzedim/caddy-proxy-manager-{caddy,web}:<tag>-selectel`. To track an upstream release: bump `UPSTREAM_TAG` + `IMAGE_TAG` in the workflow, dispatch it, swap the tags in compose (if the patch anchors drift, the patch step fails loudly). Selectel creds in the panel would be the `cert-sync` service user (keystone user/password/account_id/project_name — same as cert-sync uses); Selectel is NOT needed today — issuance for `cmnw.ru` stays at Selectel CM with cert-sync delivery. Container discovery goes through `cmnw-socket-proxy` (tecnativa/docker-socket-proxy) — nothing in this stack mounts the raw docker socket. `cmnw-l4-port-manager` syncs panel-created L4 (TCP/UDP) listeners; unused so far.

Domains: `cmnw.me`, `cmnw.xyz`, `cmnw.ru` — `me`/`xyz` traffic arrives through Cloudflare (orange-cloud). Ports 80/443 tcp+udp (HTTP/3/QUIC). **Geo-splitting (2026-10-03):** RU visitors of `cmnw.me` are 302'd to `https://cmnw.ru`, non-RU visitors of `cmnw.ru` are 302'd to `https://cmnw.me`, and `cmnw.xyz` redirects everyone to `cmnw.me` (RU then hop to `.ru`). Implemented as per-host geoblock rules in the panel; country lookup uses the DB-IP Country/ASN Lite mmdb files in the `geoip-data` volume (`/mnt/caddy-geoip`, mounted into caddy + panel as GeoLite2-Country/ASN.mmdb) — **refresh monthly** (db-ip.com free downloads; host can't fetch them directly — download elsewhere and SFTP up). The `.me` host's geoblock carries Cloudflare's IP ranges in `trusted_proxies` so the real client IP is taken from X-Forwarded-For behind the orange cloud; unknown/private IPs pass (`fail_closed: false`). The nginx era is fully retired (2026-10-03): the old stack lives only in git history (last nginx compose at the caddy cutover (2026-10-03)), a final snapshot of `/mnt/nginx` + `/mnt/nginx-ui` (configs, certs, nginx-ui DB) is archived at `/root/backups/nginx-final-20261003.tar.gz`, and the old volumes/images/host dirs are deleted.

GitLab SSH runs on host port `2222` via the `gitlab-ssh` socat sidecar in `compose.gitlab.yaml` (replaced the former nginx `stream` block); `gitlab.rb` keeps `gitlab_shell_ssh_port = 2222` so clone URLs stay correct. socat hides real client IPs from gitlab sshd — accepted trade-off; a panel-managed L4 listener can replace the sidecar later.

### Certificate automation

- **`cmnw.me` / `cmnw.xyz`** — Cloudflare Origin certificates (issued in the CF dashboard, valid until 2040-12-28), imported into the panel as custom certificates. A switch to panel-managed ACME wildcards via Cloudflare DNS-01 was attempted at cutover and is currently **blocked by a Cloudflare anomaly**: TXT records created at `_acme-challenge.<domain>` exist in the API and bump the zone serial but never become visible via public recursion (any other name publishes instantly; direct queries to Cloudflare auth NS time out). Two managed wildcard certs (`cmnw.me-wildcard`, `cmnw.xyz-wildcard`) sit parked in the panel with the CF DNS provider configured — retry the switch by re-assigning the me/xyz hosts to them once `_acme-challenge` TXTs serve publicly (test: create a TXT, `nslookup -type=TXT _acme-challenge.cmnw.me 8.8.8.8`). NB: switch ALL hosts of a domain group at once — Caddy skips auto-management for names already covered by a loaded cert, so partial switches never issue; panel DNS Resolvers must stay set (1.0.0.1/208.67.222.222/9.9.9.9) or the propagation check queries auth NS directly and hangs. Both domains are orange-clouded through Cloudflare.
- **`cmnw.ru`** — issued and auto-renewed by **Selectel Certificate Manager** (Let's Encrypt, DNS-01 runs automatically because the zone is hosted on Selectel DNS, delegated to `a/b/c/d.ns.selectel.ru`). Delivery into the panel is automated by the **`cmnw-cert-sync`** sidecar (built from `cert-sync/` → `ghcr.io/alexzedim/cert-sync` via `.github/workflows/build-cert-sync.yml`, local-first). **The CM API does not accept static API keys** (the panel's «API-ключи» return 401) — it requires a Keystone project token: the sidecar authenticates as the Selectel service user `cert-sync` (role `member` on project `cmnw`, IAM → Сервисные пользователи; no narrower role covers Certificate Manager) via `POST https://cloud.api.selcloud.ru/identity/v3/auth/tokens` and uses the 24 h `X-Subject-Token` as `X-Auth-Token` for `GET .../certificate-manager/v1/cert/{cert_id}/ca_chain` and `.../private_key` (raw PEM). It then upserts the cert via the panel REST API (`POST/PUT /api/v1/certificates`, Bearer token from the panel's API tokens). Selectel is **not** among the panel's DNS-01 providers — that is why issuance stays at Selectel CM and only delivery is synced. The wildcard cert `*.cmnw.ru`+apex (`cmnw-ru-wildcard`, ordered 2026-10-03) covers the LAN-only `oracle-*.cmnw.ru` vhosts; the older apex-only cert (`cmnw`) stays valid until 2026-11-19. Expiry warnings land in `docker logs cmnw-cert-sync`.

### Smart home — Home Assistant (single service)

`compose.home.yaml` is **Home Assistant only** (patch-build image `ghcr.io/alexzedim/home-assistant:<tag>-nuc` — upstream + НУЦ CA bundle, see below) with `network_mode: host` — required for mDNS discovery and local control of LAN devices; it binds **8123 directly on the host** and stays **LAN-only** (`http://128.0.0.255:8123`). No privileged mode, no MQTT/Zigbee/Z-Wave sidecars — all devices are Wi-Fi/cloud. Config lives in the `home-assistant-config` volume (`/mnt/home-assistant`; no chown needed, the container runs as root). Device integrations are HACS custom components (installed into `/config/custom_components`, not tracked in this repo): a smart speaker (media_player + TTS, QR-code login, mDNS local mode), smart bulbs + hub (cloud-only vendor OAuth — no local/Matter path), and a robot vacuum (local control). Device specifics (vendors, models, hostnames, LAN IPs) are intentionally **not** committed to this public repo — keep it that way.

The pre-2026-10-05 six-service smart-home template (mosquitto, node-red, zigbee2mqtt, zwave-js-ui, influxdb, traefik labels) was never deployed and is deleted — it lives in git history. Deployed as a Portainer **Repository stack** (public GitHub `alexzedim/core`, master, compose path `compose.home.yaml`); its env (`TZ`) comes from `../envs/home/.stack.env` → Portainer stack env — the repo is public, so no env values are ever committed to it.

HA is also reachable at `https://home.cmnw.ru` (panel proxy host, wildcard cert, websocket on, geoblock fail_closed allowing the LAN `128.0.0.0/16` + LAN v6 prefix + the voice-assistant cloud's published CIDRs). `external_url`/`internal_url` are set in HA. NB: **HA 2026.9+ ignores `http:` YAML** (migrated to the store on first boot) — reverse-proxy settings (`use_x_forwarded_for`, `trusted_proxies`) live in `/config/.storage/http`; edit that file only while the container is stopped. Backups: HA-native weekly schedule (keep 4 copies → `/mnt/home-assistant/backups`) plus a host cron copying the newest `.tar` to `/root/backups/`. Updates: bump the image tag in `compose.home.yaml`, push, "Update the stack" in Portainer.

**НУЦ (Минцифры) certs — required by one vendor cloud integration:** its gateway serves a Russian-Trusted-CA chain that the stock HA image does not trust → the integration goes `setup_retry` (SSL `unable to get local issuer certificate`) and all its entities go `unavailable`. Solution: **patch-build image** `ghcr.io/alexzedim/home-assistant:<tag>-nuc` (Dockerfile in `home-assistant/`, built by `.github/workflows/build-home-assistant.yml`) — the official Gosuslugi bundle (`gu-st.ru/content/downloads/Russian_Trusted_{Root_CA,Sub_CA,Sub_CA_2024}.cer`, LF PEM, committed at `home-assistant/nuc_official.pem`) is folded into the system CA store and certifi at build time. HA version updates: bump the tag in the Dockerfile FROM, the workflow tags and compose, rebuild, update the stack. Verified 2026-10-07, automated 2026-10-09.

### Shared External Network: `cmnw`

Multiple stacks join a pre-created external network named `cmnw` so services can reach each other across compose files. If this network doesn't exist yet, create it: `docker network create cmnw`.

### Volume Bind Mounts

Several named volumes bind-mount to host paths under `/mnt/`:

| Volume | Host Path | Stack |
|--------|-----------|-------|
| `postgres` | `/mnt/postgres` | storage |
| `rabbitmq` | `/mnt/rabbitmq` | storage |
| `pgvector` | `/mnt/pgvector` | storage |
| `caddy-data` | `/mnt/caddy` | routing |
| `caddy-config` | `/mnt/caddy-config` | routing |
| `caddy-logs` | `/mnt/caddy/logs` | routing |
| `caddy-manager-data` | `/mnt/caddy-manager` | routing — panel SQLite, source of truth, **back this up** |
| `loki` | `/mnt/loki` | analytics |
| `home-assistant-config` | `/mnt/home-assistant` | home |

These host directories must exist before `up -d` or the volume will fail to mount, **and ownership must match the container user** (`/mnt/caddy*` → uid 10000 for the panel's caddy image, `/mnt/caddy-manager` → uid 10001, like `/mnt/loki` → 10001) — otherwise Caddy ACME fails with `mkdir /data/caddy: permission denied`:

```bash
sudo mkdir -p /mnt/caddy /mnt/caddy-config /mnt/caddy/logs /mnt/caddy-manager /mnt/caddy-l4
sudo chown 10000:10000 /mnt/caddy /mnt/caddy-config /mnt/caddy/logs
sudo chown 10001:10001 /mnt/caddy-manager
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

Images built by the repo's GitHub Actions workflows are available on the deploy host without a registry pull; GHCR (`ghcr.io/alexzedim/*`) is the backup/source of truth and deploys use the local copy.

- `compose.oracle.yaml` and `compose.oraculum.yaml` set `pull_policy: if_not_present` on all `ghcr.io/alexzedim/*` services: deploy uses the local image and pulls from GHCR only if it's somehow missing locally. Without this, compose's default policy re-pulls `:latest` from GHCR on every deploy. Third-party images (lightrag etc.) keep the default policy.
- Stack webhooks (`pullimage`) and the "Re-pull image" GitOps toggle do nothing here; no stack uses GitOps webhooks/polling — deploys are manual ("Pull and redeploy" / "Update the stack"), which runs a plain `docker compose up -d`, so the file-level `pull_policy` is always in effect. Never check a "Re-pull image" option when you want the local copy.
- Quick health check: in Portainer's stack containers table, an image shown as a bare `sha256:…` fragment means the container was created from a registry pull; the image tag means it was created from the local build.
- `docker-prune` (in `compose.git.yaml`) is a nightly janitor (04:30 MSK, `DOCKER_PRUNE_CRON`) that prunes stopped containers, unused images, and build cache older than `DOCKER_PRUNE_RETENTION` (default `48h`). Images used by any container are never removed; volumes are never pruned. Logs: `docker logs docker-prune`.

---

## Stacks

| File | Services | Networks |
|------|----------|----------|
| `compose.storage.yaml` | PostgreSQL 17.4 (vanilla), Redis 7.4.3, MinIO, RabbitMQ 4.2.2, RabbitScout, pgvector 0.8.6 (LightRAG DB, :5433) | `storage-network`, `cmnw` |
| `compose.routing.yaml` | Caddy (fuomag9 panel image), caddy-proxy-manager (web UI), docker-socket-proxy, l4-port-manager, cert-sync | `edge`, `cmnw`, `routing-internal`, `socket-proxy` |
| `compose.analytics.yaml` | Prometheus, Grafana, Loki, Promtail, Postgres Exporter | `loki`, `cmnw` |
| `compose.home.yaml` | Home Assistant 2026.9.4 (LAN-only :8123, mDNS discovery) | `host` |
| `compose.git.yaml` | 5× GitHub Actions runners (3× cmnw, 2× oraculum), docker-prune janitor | `runner-network` |
| `compose.gitlab.yaml` | GitLab CE + gitlab-ssh (socat relay, host `:2222` → `gitlab:22`) | `cmnw` |
| `compose.oracle.yaml` | 4× vpn-oracle (AdGuard VPN gateways) + oracle / oracle-1d / oracle-2bd / oracle-3s | `oraculum`, `cmnw` (ext) |
| `compose.oraculum.yaml` | indexator, oracular, archivum, gateway, lightrag | `oraculum` |
| `compose.ai.yaml` | GitHub MCP, Grafana MCP | `cmnw` |
| `compose.control.yaml` | Portainer | default |
| `compose.ai-local.yaml` | Ollama + Open WebUI with NVIDIA GPU passthrough | `ai-local-network` |

---

## Key Conventions

- **File naming:** `compose.<category>.yaml`
- **Top of each file:** `name: '<category>'` (no `version:` field — it was dropped repo-wide as obsolete)
- **4-space indentation** in all YAML
- **Ports:** quote as strings (`'5432:5432'`), except where the existing file already uses unquoted — be consistent within each file
- **Comments:** in compose files, comments are allowed ONLY in the top-of-file header block — no inline or per-service comments anywhere else in the file; move all explanation into the header
- **Env vars:** use `${VAR_NAME}` in compose files. The committed **`.env.example`** is the canonical template listing every variable the stacks reference — non-secret defaults filled in, secrets blanked. Copy it to `.env` per host and fill in real values. The root `.env` is gitignored (see `.gitignore`: `!/.env` then `.env` — the later pattern wins, so `.env` is ignored while `.env.example` is committed). On the production server, secrets are injected via Portainer env or `stack.env` (`env_file`), never committed. When adding a new `${VAR}` to a compose file, add it to `.env.example` in the matching section.
- **Image tags:** pin specific versions (e.g., `postgres:17.4`), never `:latest` for production services
- **`kebab-case`** for all resource names (networks, volumes, services)
- **`restart: always`** for infrastructure, `unless-stopped` for discretionary services
- **`container_name:`** on every service to avoid auto-generated names

### Intentional Exceptions

- **Home Assistant:** `network_mode: host` — mDNS discovery and local device control on the LAN; binds 8123 directly, LAN-only
- **docker-socket-proxy (routing):** mounts `/var/run/docker.sock:ro` behind a restricted API proxy — the panel's only window onto Docker
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

# Routing config changes are made in the caddy-proxy-manager UI
# (http://128.0.0.255:3000) — it hot-reloads Caddy itself
docker logs -f cmnw-caddy
```

---

## Adding a New Service

1. Add to an existing `compose.<category>.yaml` or create a new one
2. Add env vars to **`.env.example`** (committed template) with a section header (`# ==== Section ====`) — non-secret defaults filled, secrets blank. Then copy the new vars into your local `.env` with real values.
3. For cross-stack connectivity, join the `cmnw` external network
4. For persistent data, add a named volume (use bind mount to `/mnt/<name>` if the data needs a known host path)
5. If the service should be reachable via HTTPS, add a proxy host in the caddy-proxy-manager UI (or its REST API under `/api/v1/`)
6. Validate: `docker compose -f compose.<category>.yaml config`
7. Deploy: `docker compose -f compose.<category>.yaml up -d`
