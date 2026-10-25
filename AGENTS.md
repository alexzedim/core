# AGENTS.md — Core Infrastructure Repository (public)

**This is infrastructure-as-code for a private self-hosted server, not application source code.** There are no tests, no linting, and no build step. All changes are validated with `docker compose -f compose.<stack>.yaml config` and applied with `up -d`.

---

## Security model — READ THIS FIRST

This repository is **public on the internet**. It deliberately contains **zero operational specifics**: no IP addresses, no MACs, no internal hostnames or DNS details, no port maps of internal services, no network topology, no ACL/upstream lists, no deploy paths, no credentials or their locations, no device specifics, no incident history that would reveal defensive posture.

All of that lives in **`AGENTS-LOCAL.md`** — a sibling file in the repo root that is **gitignored, never committed, and absent from git history** (canonical offline copies are kept on the deploy host, root-only). If `AGENTS-LOCAL.md` is missing on your machine, obtain it from the host vault; **never** reconstruct sensitive details into public files, commit messages, PRs, or GitHub artifacts.

When editing this repo, ask before committing: *does this line reveal how to reach, probe, or bypass anything?* If yes — it belongs in `AGENTS-LOCAL.md`.

---

## Stack inventory

Compose files follow `compose.<category>.yaml`, each with `name: '<category>'` at the top. Functional groups (per-stack services, networks, volumes and their interconnections are documented in `AGENTS-LOCAL.md`):

- **routing** — TLS-terminating reverse proxy + its management panel (patch-built images from this repo's workflows), sidecars for certificate delivery and panel-managed L4 listeners
- **network** — the house DNS resolver (encrypted client transports, filtering, offline-snapshot autonomy) + VPN egress gateways
- **storage** — shared PostgreSQL (two instances), Redis, object storage, message broker + exporters
- **analytics** — Prometheus, Grafana, Loki, Promtail, exporters
- **home** — a single smart-home service (host network mode, LAN-only)
- **gitlab / git** — self-hosted Git + CI runners
- **oracle / oraculum** — scraper fleet and RAG services
- **ai / ai-platform / ai-local** — lab stacks (one with GPU passthrough)
- **control** — Portainer

---

## CI/CD Image Flow — local-first deploys

Images built by the repo's GitHub Actions workflows are available on the deploy host without a registry pull; GHCR (`ghcr.io/<owner>/*`) is the backup/source of truth and deploys use the local copy.

- `compose.network.yaml`, `compose.oracle.yaml` and `compose.oraculum.yaml` set `pull_policy: if_not_present` on all self-built `ghcr.io/<owner>/*` services: deploy uses the local image and pulls from GHCR only if it's somehow missing locally. Without this, compose's default policy re-pulls `:latest` from GHCR on every deploy. Third-party images keep the default policy.
- Stack webhooks (`pullimage`) and the "Re-pull image" GitOps toggle do nothing here; no stack uses GitOps webhooks/polling — deploys are manual ("Pull and redeploy" / "Update the stack"), which runs a plain `docker compose up -d`, so the file-level `pull_policy` is always in effect. Never check a "Re-pull image" option when you want the local copy.
- Quick health check: in Portainer's stack containers table, an image shown as a bare `sha256:…` fragment means the container was created from a registry pull; the image tag means it was created from the local build.
- `docker-prune` (in the git stack) is a nightly janitor that prunes stopped containers, unused images, and build cache past a retention window. Images used by any container are never removed; volumes are never pruned.

---

## Portainer git-stack gotchas (CE 2.45)

- There is **no stack-create API** in CE 2.45 (`POST /api/stacks` → 405) — Repository stacks are created via the UI (Source = the GitOps source for this repo, env pasted in Advanced mode; the UI env persists to the DB and `stack.env`).
- Every git deploy turns **file** bind sources into directories — both repo-relative and absolute host paths — so per-file mounts never come up; "Additional paths" in the Git settings are passed to compose as extra `-f` overlay files (breaks non-YAML files with "top-level object must be a mapping"). Workaround used here: such configs live in pre-seeded external volumes.
- `PUT /api/stacks/{id}/git/redeploy` with a full `Env` payload both deploys and persists the env to the stack DB record — never send `Env: []` (it wipes the env).

---

## Key Conventions

- **File naming:** `compose.<category>.yaml`
- **Top of each file:** `name: '<category>'` (no `version:` field)
- **4-space indentation** in all YAML
- **Ports:** quote as strings (`'5432:5432'`), consistent within each file
- **Comments:** in compose files, comments are allowed ONLY in the top-of-file header block and in `# ===...===` section banners above a service — no inline or per-service comments anywhere else; move all explanation into the header or a banner
- **Env vars:** use `${VAR_NAME}` in compose files. The committed **`.env.example`** is the canonical template listing every variable the stacks reference — non-secret defaults filled in, secrets blanked. On the production server, secrets are injected via Portainer env or `stack.env` (`env_file`), never committed. When adding a new `${VAR}` to a compose file, add it to `.env.example` in the matching section.
- **Image tags:** pin specific versions, never `:latest` for production services
- **`kebab-case`** for all resource names (networks, volumes, services)
- **`restart: always`** for infrastructure, `unless-stopped` for discretionary services
- **`container_name:`** on every service to avoid auto-generated names

### Intentional Exceptions (reasons in AGENTS-LOCAL.md)

- One smart-home service: `network_mode: host` (LAN discovery protocols), LAN-only
- Docker-socket mounts behind a restricted proxy for the panel; direct socket for Portainer and CI runners (required for their function)
- One egress service: `network_mode: host` (reachability of its upstream API)
- One lab stack: `deploy.resources.reservations.devices` for NVIDIA GPU passthrough

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
```

Reverse-proxy configuration is managed in the panel UI (address in `AGENTS-LOCAL.md`), which hot-reloads the proxy; deploy paths, stack IDs and emergency-deploy procedures are likewise in `AGENTS-LOCAL.md`.

---

## Adding a New Service

1. Add to an existing `compose.<category>.yaml` or create a new one
2. Add env vars to **`.env.example`** with a section header — non-secret defaults filled, secrets blank; then copy into the real env store
3. For cross-stack connectivity, join the shared external network (name in `AGENTS-LOCAL.md`)
4. For persistent data, add a named volume (bind-mount layout and disk split rules in `AGENTS-LOCAL.md`)
5. If the service should be reachable via HTTPS, add a proxy host in the panel UI
6. Validate: `docker compose -f compose.<category>.yaml config`
7. Deploy: `docker compose -f compose.<category>.yaml up -d`
