# Stack Network Fix — Resolving the `128.0.0.255` hairpin outage

## Root cause

`128.0.0.255` is in the IANA-reserved `128.0.0.0/8` (benchmarking) block. It was
used throughout the stack as a "host-IP hairpin" so containers in one compose
network could reach services in another by routing out to the host and back in
via published ports. This is fragile and **already caused one outage** — see
`.kilo/plans/1780063884225-stellar-panda.md` (GitLab → Redis, same pattern).

The current production outage is the same bug class:

- All `/api/*` requests to cmnw.me return **502 from Cloudflare**.
- The Next.js rewrite in `cmnw-next/next.config.js` forwarded `/api/*` to
  `http://128.0.0.255:8081` — that's **Next.js's own port**, not the API, so the
  rewrite looped/hung. See `cmnw-next/config/api-origin.js`.
- Separately, `cmnw-api` likely can't reach Postgres (`POSTGRES_HOST=128.0.0.255`
  in the server `stack.env`), because Postgres was only on `storage-network` and
  not reachable by service name from the app containers.

## What changed in this repo

### `cmnw-next` (application)
- **`config/api-origin.js`** — `INTERNAL_API_ORIGIN` changed from
  `http://128.0.0.255:8081` (self-loop) to `http://cmnw-api:8080` (the actual
  API service on the `cmnw` network). Requires a rebuild + redeploy of the
  `cmnw-next` image.

### `core` (infrastructure)
- **`nginx/conf.d/cmnw.conf`** — Added `Upgrade` / `Connection` /
  `proxy_cache_bypass` headers to all four `/api` location blocks (cmnw.me and
  cmnw.ru), so SSE / WebSocket endpoints work through the API proxy path, not
  just the Next.js path.
- **`docker-compose.storage.yml`** — Added the `cmnw` external network to
  `postgres`, `minio`, and `rabbitmq` (Redis already had it). All app containers
  on `cmnw` can now reach storage by **Docker service name** instead of the
  `128.0.0.255` hairpin.
- **`docker-compose.analytics.yml`** — Prometheus scrape targets for `cmnw-api`
  and `minio` switched from `128.0.0.255` to service names. Prometheus is on the
  `cmnw` network, so DNS resolution now works. Other targets (Home Assistant on
  host network, exporters) intentionally left as-is.

### Not changed (intentional)
- **`cmnw/.env`** — This is the **dev-local** file (`NODE_ENV=development`).
  Editing it would break local dev. Production values come from `stack.env` on
  the server — see "Server-side actions" below.

---

## Deployment order (on the server)

The storage network change must come **before** the app restart, so storage is
reachable by name when the app boots.

```bash
# 1. Recreate storage stack so postgres/minio/rabbitmq join the cmnw network
docker-compose -f docker-compose.storage.yml up -d

# 2. Verify DNS from an app container
docker exec cmnw-api getent hosts postgres     # should resolve
docker exec cmnw-api getent hosts cmnw-api     # self-check
docker exec cmnw-nginx getent hosts cmnw-api   # nginx must reach the API

# 3. Reload nginx (config is a shared volume)
docker exec cmnw-nginx nginx -t && docker exec cmnw-nginx nginx -s reload

# 4. Recreate analytics so Prometheus rescrapes by service name
docker-compose -f docker-compose.analytics.yml up -d
```

## Server-side actions (cannot be done from this repo)

### Update `stack.env` for the cmnw stack

The server's `stack.env` (loaded by `cmnw/docker-compose.core.yml`) must switch
host settings from `128.0.0.255` to Docker service names. Set at minimum:

```dotenv
POSTGRES_HOST=postgres
REDIS_HOST=redis
RABBITMQ_HOST=rabbitmq
S3_HOST=http://minio:9000
DATA_SOURCE_NAME=postgresql://core:<password>@postgres:5432/cmnw?sslmode=disable
```

Leave any **host-network-only** services (e.g. Home Assistant) on the host IP —
those genuinely can't be reached by service name.

After editing `stack.env`, recreate the app containers:

```bash
docker-compose -f docker-compose.core.yml up -d
```

### Rebuild + redeploy `cmnw-next`

The `api-origin.js` change is build-time (CommonJS `require`), so the image must
be rebuilt:

```bash
# in the cmnw-next repo, on the deployment runner
docker build -t ghcr.io/alexzedim/cmnw-next:latest .
docker push ghcr.io/alexzedim/cmnw-next:latest
# then on the server
docker-compose -f docker-compose.core.yml pull next
docker-compose -f docker-compose.core.yml up -d next
```

## Verification

```bash
# From nginx's perspective, the upstream must resolve and answer
docker exec cmnw-nginx wget -qO- http://cmnw-api:8080/api/metrics | head

# From the public edge
curl -sI https://cmnw.me/api/app/metrics   # expect 200, not 502
```

---

## Still open: 404 on `/guilds`, `/characters`, `/market`

Unrelated to the outage. These routes do **not exist** in the deployed
`cmnw-next` build. The app router only has `app/guild/[guid]/` (singular,
dynamic), `app/character/`, etc. Either:

1. The nav links point to `/guilds` but the real route is `/guild/[guid]`
   (singular) — fix the link, **or**
2. Listing pages were never created — add `app/guilds/page.tsx` etc.

Confirmed live: `/guilds` returns Next.js's default 404 page as `text/html`
served from the edge, so the route is genuinely absent from the build, not a
proxy issue.
