# AGENTS.md — Core Infrastructure Repository

**This is infrastructure-as-code for a self-hosted server (`core.cmnw`), not application source code.** There are no tests, no linting, and no build step. All changes are validated with `docker compose -f compose.<stack>.yaml config` and applied with `up -d`.

---

## Architecture

### Reverse Proxy — Caddy + caddy-proxy-manager

Caddy (`cmnw-caddy`) handles all SSL termination and reverse proxying via `compose.routing.yaml`. **caddy-proxy-manager** ([fuomag9/caddy-proxy-manager](https://github.com/fuomag9/caddy-proxy-manager), web UI at `http://128.0.0.255:3001`, LAN-only — :3000 is grafana) owns the routing config — proxy hosts, location rules, access lists, certificates, L4 listeners — in its SQLite DB at `/srv/docker/caddy-manager` (**include it in host backups — it is the source of truth; there is no Caddyfile on disk**) and pushes generated JSON to Caddy's admin API (`http://cmnw-caddy:2019`, `routing-internal` network) with zero-downtime reloads. Config changes are made in the panel UI, not in this repo. The routing stack is a Portainer **Repository** stack (stack id 103, `alexzedim/core` @ master, compose path `compose.routing.yaml`; converted 2026-10-12 from a legacy standalone record that the API could not delete — removal required a temporary single-node `docker swarm init`). The emergency copy at `/root/deploy/routing` (compose + `stack.env`) remains the SSH-emergency deploy path — keep it in sync with the repo file.

Panel images are **our own patch-build** of upstream ([ingres-si/ingressi](https://github.com/ingres-si/ingressi) — formerly `fuomag9/caddy-proxy-manager`, GitHub redirects the old name; tag-pinned): `.github/workflows/build-caddy-panel.yml` clones the upstream at `UPSTREAM_TAG`, applies `caddy-panel/apply-selectel.cjs` (adds `caddy-dns/selectel` to the xcaddy build + the panel provider registry, sets builder `GOPROXY=goproxy.cn,direct` — the runner's IPv4-only docker bridge gets connection-reset from Google's module-zip store — and emits caddy-l4 `postgres_tls` + `tls` for L4 hosts with meta `{"postgresSsl": true}`, see "External database endpoints") and pushes `ghcr.io/alexzedim/caddy-proxy-manager-{caddy,web}:<tag>-selectel`. To track an upstream release: bump `UPSTREAM_TAG` + `IMAGE_TAG` in the workflow, dispatch it, swap the tags in compose (if the patch anchors drift, the patch step fails loudly). Selectel creds in the panel would be the `cert-sync` service user (keystone user/password/account_id/project_name — same as cert-sync uses); Selectel is NOT needed today — issuance for `cmnw.ru` stays at Selectel CM with cert-sync delivery. Container discovery goes through `cmnw-socket-proxy` (tecnativa/docker-socket-proxy) — nothing in this stack mounts the raw docker socket. `cmnw-l4-port-manager` syncs panel-created L4 (TCP/UDP) listeners; unused so far.

Domains: `cmnw.me`, `cmnw.xyz`, `cmnw.ru` — `me`/`xyz` traffic arrives through Cloudflare (orange-cloud). Ports 80/443 tcp+udp (HTTP/3/QUIC). **Geo-splitting (2026-10-03):** RU visitors of `cmnw.me` are 302'd to `https://cmnw.ru`, non-RU visitors of `cmnw.ru` are 302'd to `https://cmnw.me`, and `cmnw.xyz` redirects everyone to `cmnw.me` (RU then hop to `.ru`). Implemented as per-host geoblock rules in the panel; country lookup uses the DB-IP Country/ASN Lite mmdb files in the `geoip-data` volume (`/srv/docker/caddy-geoip`, mounted into caddy + panel as GeoLite2-Country/ASN.mmdb) — **refresh monthly** (db-ip.com free downloads; host can't fetch them directly — download elsewhere and SFTP up). The `.me` host's geoblock carries Cloudflare's IP ranges in `trusted_proxies` so the real client IP is taken from X-Forwarded-For behind the orange cloud; unknown/private IPs pass (`fail_closed: false`). The nginx era is fully retired (2026-10-03): the old stack lives only in git history (last nginx compose at the caddy cutover (2026-10-03)), a final snapshot of `/mnt/nginx` + `/mnt/nginx-ui` (configs, certs, nginx-ui DB) is archived at `/root/backups/nginx-final-20261003.tar.gz`, and the old volumes/images/host dirs are deleted.

GitLab SSH runs on host port `2222` via the `gitlab-ssh` socat sidecar in `compose.gitlab.yaml` (replaced the former nginx `stream` block); `gitlab.rb` keeps `gitlab_shell_ssh_port = 2222` so clone URLs stay correct. socat hides real client IPs from gitlab sshd — accepted trade-off; a panel-managed L4 listener can replace the sidecar later.

### Certificate automation

- **`cmnw.me` / `cmnw.xyz`** — Cloudflare Origin certificates (issued in the CF dashboard, valid until 2040-12-28), imported into the panel as custom certificates. A switch to panel-managed ACME wildcards via Cloudflare DNS-01 was attempted at cutover and is currently **blocked by a Cloudflare anomaly**: TXT records created at `_acme-challenge.<domain>` exist in the API and bump the zone serial but never become visible via public recursion (any other name publishes instantly; direct queries to Cloudflare auth NS time out). Two managed wildcard certs (`cmnw.me-wildcard`, `cmnw.xyz-wildcard`) sit parked in the panel with the CF DNS provider configured — retry the switch by re-assigning the me/xyz hosts to them once `_acme-challenge` TXTs serve publicly (test: create a TXT, `nslookup -type=TXT _acme-challenge.cmnw.me 8.8.8.8`). NB: switch ALL hosts of a domain group at once — Caddy skips auto-management for names already covered by a loaded cert, so partial switches never issue; panel DNS Resolvers must stay set (1.0.0.1/208.67.222.222/9.9.9.9) or the propagation check queries auth NS directly and hangs. Both domains are orange-clouded through Cloudflare.
- **`cmnw.ru`** — issued and auto-renewed by **Selectel Certificate Manager** (Let's Encrypt, DNS-01 runs automatically because the zone is hosted on Selectel DNS, delegated to `a/b/c/d.ns.selectel.ru`). Delivery into the panel is automated by the **`cmnw-cert-sync`** sidecar (built from `cert-sync/` → `ghcr.io/alexzedim/cert-sync` via `.github/workflows/build-cert-sync.yml`, local-first). Since **cert-sync 1.1.0** the same run also writes `cert.pem`/`key.pem` into `/srv/docker/adguard/tls` (env `AGH_TLS_DIR` + bind mount in `compose.routing.yaml`) — that dir feeds the AGH DoT server; writes are atomic (tmp+rename, 644/600) and AGH reloads path-specified certs without a restart. All remote calls retry with backoff inside a run (container-DNS blips during AGH restarts caused a cert-sync outage window 2026-10-23…24). Before 1.1.0 the tls dir was refreshed manually — deployed on the next routing-stack redeploy (image is local-first; rebuild lands on the self-hosted runner host). **The CM API does not accept static API keys** (the panel's «API-ключи» return 401) — it requires a Keystone project token: the sidecar authenticates as the Selectel service user `cert-sync` (role `member` on project `cmnw`, IAM → Сервисные пользователи; no narrower role covers Certificate Manager) via `POST https://cloud.api.selcloud.ru/identity/v3/auth/tokens` and uses the 24 h `X-Subject-Token` as `X-Auth-Token` for `GET .../certificate-manager/v1/cert/{cert_id}/ca_chain` and `.../private_key` (raw PEM). It then upserts the cert via the panel REST API (`POST/PUT /api/v1/certificates`, Bearer token from the panel's API tokens). Selectel is **not** among the panel's DNS-01 providers — that is why issuance stays at Selectel CM and only delivery is synced. The wildcard cert `*.cmnw.ru`+apex (`cmnw-ru-wildcard`, ordered 2026-10-03) covers the LAN-only `oracle-*.cmnw.ru` vhosts; the older apex-only cert (`cmnw`) stays valid until 2026-11-19. Expiry warnings land in `docker logs cmnw-cert-sync`.

### External database endpoints — TLS via Caddy L4 (2026-10-12)

Postgres (:5432) and pgvector (:5433) are reachable from the internet over TLS through two panel-managed **L4 proxy hosts**: `pg-main-external-tls` (:25432 → `postgres:5432`) and `pgvector-external-tls` (:25433 → `pgvector:5432`). TLS terminates at Caddy with the cmnw.ru wildcard (SNI matcher `cmnw.ru` + `*.cmnw.ru`); the Caddy→backend hop is plaintext over docker networks — same trust domain as every other Caddy→backend hop. Both hosts carry a panel **geoblock** (2026-10-12, RU-only): a caddy-l4 `blocker` route blocks every continent and exempts `RU` plus private/LAN ranges (RFC1918, loopback, `128.0.0.0/23`, `128.0.30.0/24`) — private sources carry no geo and pass by default. Connect with `sslmode=verify-full` (public-CA cert, system trust stores work): `postgresql://ai-documents:<pw>@cmnw.ru:25432/wiki` (also `ai-documents-dev`, `ai-documents-exp`) and `postgresql://ai-documents:<pw>@cmnw.ru:25433/lightrag`. The `ai-documents` login role exists on BOTH instances with the same password (vault: `../envs/storage/.stack.env`, `AI_DOCUMENTS_PG_*`); it has full R/W in exactly those DBs — tables are owned by `core`/`lightrag` and future tables are covered by `ALTER DEFAULT PRIVILEGES` — and no grants anywhere else. NB: in-container loopback is pg_hba `trust` (passwords only enforced on external connections via `host all all scram-sha-256`); `sslmode=disable` clients get the connection closed on purpose — TLS is mandatory. Keenetic forwards `25432/25433 tcp` → core (UPnP is off on the router — static forwards only).

**Panel patch:** upstream emits the plain L4 `tls` handler, which breaks every standard libpq/JDBC client — they open with a Postgres SSLRequest message before the ClientHello, so the handshake dies with "server closed the connection unexpectedly". Patch #5 in `caddy-panel/apply-selectel.cjs` makes an L4 host with meta `{"postgresSsl": true}` emit caddy-l4's `postgres_tls` handler **before** the `tls` handler — `postgres_tls` only consumes the SSLRequest and replies 'S', the `tls` handler does the actual termination. The panel UI has no meta field — set it via the API (`PUT /api/v1/l4-proxy-hosts/{id}`); admin session auth works (the cert-sync token is certificates-scoped and gets 401 elsewhere). **NB: updating an L4 host through the structured fields (e.g. `geoblock`) rebuilds `meta` and silently drops unknown keys — every such update must carry `meta: {"postgresSsl": true}` too** (symptom when lost: `tls: first record does not look like a TLS handshake` in caddy logs, psql dies with "server closed the connection unexpectedly"). L4 listens must avoid 80/443/2019 (reserved — SO_REUSEPORT would silently split connections), and every new L4 port needs a matching published port in `compose.routing.yaml` + a router forward. Keenetic forwards live on PPPoE0 (Rostelecom), MAC-targeted to core like the 80/443/22 rules (`ip static tcp PPPoE0 25432 22:36:4d:08:c6:d3 !postgres`, `...25433 !pgvector`); hairpin NAT from the LAN works (verified via the WAN A-record).

### AdGuard — Home + VPN fleet (network stack)

Two different AdGuard products, deliberately in one stack (`compose.network.yaml`, project `network`, deployed as a Portainer **Repository stack** off this public repo — master, compose path `compose.network.yaml`; envs synced with `../envs/network/.stack.env`, delivered to the gateways via `env_file: stack.env`):

- **AdGuard Home** (`adguard-home`) — the house resolver and the only DNS endpoint in the chain: plain DNS on `128.0.0.255:53` (kept for the host and docker containers) plus a **DoT+DoQ server on :853** (`server_name: adguard.cmnw.ru`, `tls:` block in `AdGuardHome.yaml`); the wildcard `*.cmnw.ru` PEMs live at `/srv/docker/adguard/tls/{cert.pem,key.pem}` (bind-mounted ro, AGH reloads them on change). Ports 53+853 are published on `128.0.0.255` and (docker dual-bind) on the static HE v6 address — **`allowed_clients` is LAN-only (2026-10-24)**: loopback, `128.0.0.0/16`, RFC1918 docker ranges, `fe80::/10`, HE LAN `2001:470:28:284::/64`, both ULA /48s — that is what keeps the v6-published resolver off the internet. **The Keenetic router is the sole DHCP DNS for LAN clients (v4+v6)** and resolves through **DoT :853 → AGH** (router side: component «DNS-over-TLS proxy», `dns-proxy tls upstream 128.0.0.255 853 sni adguard.cmnw.ru`, `ip host adguard.cmnw.ru 128.0.0.255`, `interface PPPoE0 ipcp no name-servers`, `no dns-proxy rebind-protect` — rebind-protect would drop the `*.cmnw` → `128.0.0.x` answers; full batch: `/root/deploy/router-dns-dot.md` on the host). Consequence: AGH sees LAN queries as one client (the router) — per-device AGH stats are gone by design. Upstreams are NOT the router: three DoH resolvers in `load_balance` — AdGuard DNS private endpoint (`https://d.adguard-dns.com/dns-query/<private-id>` — credential-like, never commit the id), `https://dns.sb/dns-query`, `https://dns.quad9.net/dns-query` — and the fallback is DoH quad9 as well (the old plaintext `tcp://94.140.14.14` is gone; **all upstreams are encrypted** — TSPU has been RST-ing :853 to foreign resolvers since 2026-08, so DoT/DoQ *upstreams* would be the wrong choice; the LAN-internal DoT hop from the router is unaffected). Bootstrap `94.140.14.49/185.222.222.222/45.11.45.11` + quad9. `enable_dnssec: true`; cache 256 MB with `cache_ttl_min: 3600` (every answer pinned ≥1 h — rotating CDN IP sets stick a full hour per cache generation) + `cache_optimistic: true`; `use-application-dns.net` is NXDOMAIN-blocked via custom rules (disables browser DoH auto-upgrade — browsers stay on the LAN resolver). Filter lists are NOT pulled by AGH from remote URLs: host cron `dns-filters-update.sh` mirrors them into `/srv/dns-filters`, served on `128.0.0.255:8553` and referenced as filter URLs. Host tooling (Oct 2026, `/usr/local/bin`): `dns-canary` (cron every minute: blocked-domain probe + reachability → `/var/log/dns-canary.log` + `logger -t dns-canary`; v2 comment documents that transit-DNS outward is blocked on the router), `agh-cache-warm.sh`, `dns-flow-logger`, `dns-snapshot.sh`, `dns-stats-collector.py`. Host systemd-resolved uplink = AGH (`128.0.0.255`) plus the router's link-local RDNSS (`fe80::…%ens4` — harmless, both paths end at AGH). Query log is a single unrotated `work/data/querylog.json` (~2 GB after 12 days). State on host bind mounts `/srv/docker/adguard/{conf,tls,work}` — outside volumes, survives any recreate.

**ECH/ESNI reality (checked 2026-10-21 against cloudflare.com/ssl/encrypted-sni):** AGH — and the router/ISP path — reliably return type-65 HTTPS records with the `ech=` config, so a red "Secure SNI" is never a DNS fault; ECH works over IPv4 (Rostelecom path) but never engages over the LAN 6in4 IPv6 path (HE tunnel), so dual-stack sites leak SNI whenever a client picks v6; the test's "Secure DNS" row answering "weren't able to detect" is cosmetic — its every1dns.net canaries don't recognize AdGuard DoH egress. When "Secure SNI" flips red, the browser fell back to plaintext SNI on the wire — confirm live via `https://encryptedsni.com/cdn-cgi/trace` (`sni=` field, note `ip=`/`colo=`).
- **AdGuard VPN gateways** (`vpn-oracle`, `-1d`, `-2bd`, `-3s`, `-4qr`, `-5se`) — wrappers around the official AdGuard VPN CLI (image `ghcr.io/alexzedim/adguard`, the oraculum monorepo `adguard` app). Each logs in with `VPN_EMAIL`/`VPN_PASSWORD` (stack env) and connects to the location recorded in its volume's `location` file (Helsinki etc.). Healthcheck curl goes through tun0 (or direct if a `mode-direct` marker file exists in the volume).

**netns-join contract.** The scraper apps in `compose.oracle.yaml` join their gateway's network namespace CROSS-STACK via `network_mode: 'container:vpn-oracle-<x>'` — the whole pair's traffic (node + Chromium) exits through that gateway's tunnel; the pair's VNC/CDP/Selkies/TURN ports are published by the gateway. The join is pinned at app-container creation: **restarting or recreating a gateway alone orphans its app** (stale netns: no eth0, dead DNS, `ioredis ETIMEDOUT` in logs). Rules: after ANY change to the network stack, "Update the stack" for oracle too (order: network → oracle); never restart a `vpn-oracle*` container alone. Host cron `/etc/cron.d/netns-watch` → `/root/deploy/network/netns-watch.sh` compares netns inodes per pair every 5 min and `logger -t netns-watch`-alerts on divergence (no auto-fix — recreate the app via Portainer). SSH-emergency path: a copy of the stack (compose + `stack.env`) lives at `/root/deploy/oracle` — `docker compose -p oracle -f compose.oracle.yaml up -d --force-recreate` when Portainer isn't at hand (used 2026-10-10 to heal all 6 orphaned pairs).

**Gateways boot direct-first (2026-10-10).** Each wrapper probes direct egress at boot: reachable → runs WITHOUT VPN (exit = home RU IP, no tun0); unreachable → AdGuard VPN fallback to the `location` file. `api.adguard.com` is TSPU-inspected and zapret's fake ClientHellos (`tcp_seq=10000`) leak bogus SACKs that kill every docker-NAT'ed flow to it — **`api.adguard.com` must stay in the router's zapret `exclude.list`** (nfqws-keenetic-web → Lists; without it the whole fleet crash-loops on "SOCKS5 never became healthy"). Known quirk: a freshly recreated gateway volume may lack `/app/secrets` — `CoturnService` crashes with ENOENT until the dir is created inside the container.

**Cross-stack resources.** The VPN state volumes were born in the former oracle project and are attached as external volumes under their real names (`oracle_vpn-oracle-*-adguard` — logins, locations and SOCKS config survive redeploys; `vpn-oracle-5se-adguard` is the single project-scoped volume: that gateway was recreated fresh and re-logs-in on first boot). The `-geo` volumes are shared with the apps (`oracle_oracle-*-geo`: project-scoped on the oracle side, external on the network side). Networks: `cmnw` (ext) + `oraculum_oraculum` (ext — the oraculum stack's network; this is what makes gateways reachable from oraculum services).

**SOCKS5 for oraculum.** Every gateway exposes SOCKS5 on `:1080` bound to 0.0.0.0 (the CLI requires username/password auth for a non-localhost bind). One-time setup per gateway — persisted in its volume, NOT env-driven:

```bash
docker exec -u adguard vpn-oracle-<x> adguardvpn-cli config set-socks-host 0.0.0.0
docker exec -u adguard vpn-oracle-<x> adguardvpn-cli config set-socks-username "$VPN_SOCKS_USERNAME"
docker exec -u adguard vpn-oracle-<x> adguardvpn-cli config set-socks-password "$VPN_SOCKS_PASSWORD"
# then restart the container via Portainer (the wrapper re-runs `adguardvpn-cli connect` on boot)
```

Creds are recorded in `../envs/network/.stack.env` (`VPN_SOCKS_USERNAME`/`VPN_SOCKS_PASSWORD`) and in the Portainer stack env. Usage from any oraculum container: `socks5h://<user>:<pass>@vpn-oracle-<x>:1080` (DNS resolves at the proxy). NB: AdGuard VPN's default DNS upstream is **not** ad-blocking — `doubleclick.net`/`google-analytics.com` resolve fine through the tunnel; DNS ad-filtering is AdGuard Home's job (LAN) only. The oraculum `gateway` service is a separate AdGuard VPN consumer (host netns, forward proxy :3128) and stays in `compose.oraculum.yaml`.

### Smart home — Home Assistant (single service)

`compose.home.yaml` is **Home Assistant only** (patch-build image `ghcr.io/alexzedim/home-assistant:<tag>-nuc` — upstream + НУЦ CA bundle, see below) with `network_mode: host` — required for mDNS discovery and local control of LAN devices; it binds **8123 directly on the host** and stays **LAN-only** (`http://128.0.0.255:8123`). No privileged mode, no MQTT/Zigbee/Z-Wave sidecars — all devices are Wi-Fi/cloud. Config lives in the `home-assistant-config` volume (`/srv/docker/home-assistant`; no chown needed, the container runs as root). Device integrations are HACS custom components (installed into `/config/custom_components`, not tracked in this repo): a smart speaker (media_player + TTS, QR-code login, mDNS local mode), smart bulbs + hub (cloud-only vendor OAuth — no local/Matter path), and a robot vacuum (local control). Device specifics (vendors, models, hostnames, LAN IPs) are intentionally **not** committed to this public repo — keep it that way.

The pre-2026-10-05 six-service smart-home template (mosquitto, node-red, zigbee2mqtt, zwave-js-ui, influxdb, traefik labels) was never deployed and is deleted — it lives in git history. Deployed as a Portainer **Repository stack** (public GitHub `alexzedim/core`, master, compose path `compose.home.yaml`); its env (`TZ`) comes from `../envs/home/.stack.env` → Portainer stack env — the repo is public, so no env values are ever committed to it.

HA is also reachable at `https://home.cmnw.ru` (panel proxy host, wildcard cert, websocket on, geoblock fail_closed allowing the LAN `128.0.0.0/16` + LAN v6 prefix + the voice-assistant cloud's published CIDRs). `external_url`/`internal_url` are set in HA. NB: **HA 2026.9+ ignores `http:` YAML** (migrated to the store on first boot) — reverse-proxy settings (`use_x_forwarded_for`, `trusted_proxies`) live in `/config/.storage/http`; edit that file only while the container is stopped. Backups: HA-native weekly schedule (keep 4 copies → `/srv/docker/home-assistant/backups`) plus a host cron copying the newest `.tar` to `/root/backups/`. Updates: bump the image tag in `compose.home.yaml`, push, "Update the stack" in Portainer.

**НУЦ (Минцифры) certs — required by one vendor cloud integration:** its gateway serves a Russian-Trusted-CA chain that the stock HA image does not trust → the integration goes `setup_retry` (SSL `unable to get local issuer certificate`) and all its entities go `unavailable`. Solution: **patch-build image** `ghcr.io/alexzedim/home-assistant:<tag>-nuc` (Dockerfile in `home-assistant/`, built by `.github/workflows/build-home-assistant.yml`) — the official Gosuslugi bundle (`gu-st.ru/content/downloads/Russian_Trusted_{Root_CA,Sub_CA,Sub_CA_2024}.cer`, LF PEM, committed at `home-assistant/nuc_official.pem`) is folded into the system CA store and certifi at build time. HA version updates: bump the tag in the Dockerfile FROM, the workflow tags and compose, rebuild, update the stack. Verified 2026-10-07, automated 2026-10-09.

### Shared External Network: `cmnw`

Multiple stacks join a pre-created external network named `cmnw` so services can reach each other across compose files. If this network doesn't exist yet, create it: `docker network create cmnw`.

### Volume Bind Mounts — disk split (2026-10-11)

**Storage layout: nvme1n1 (`/mnt`, Kingston NV3 1TB, SMART-worn — 100% Percentage Used, critical warning 0x04 as of 2026-10-11) holds ONLY the postgres data dir; everything else lives under `/srv/docker/` on the root fs (nvme0n1). The worn disk is pending replacement — when it arrives, mkfs + mount the new fs at `/mnt/postgres` and rsync the data with the storage stack stopped; no compose change needed (`storage_postgres` keeps pointing at `/mnt/postgres`).** Named volumes bind-mount to host paths:

| Volume | Host Path | Stack |
|--------|-----------|-------|
| `postgres` | `/mnt/postgres` | storage — the only /mnt resident |
| `rabbitmq` | `/srv/docker/rabbitmq` | storage |
| `pgvector` | `/srv/docker/pgvector` | storage |
| `caddy-data` | `/srv/docker/caddy` | routing |
| `caddy-config` | `/srv/docker/caddy-config` | routing |
| `caddy-logs` | `/srv/docker/caddy/logs` | routing (nested inside caddy-data's dir, same as before) |
| `caddy-manager-data` | `/srv/docker/caddy-manager` | routing — panel SQLite, source of truth, **back this up** |
| `geoip-data` | `/srv/docker/caddy-geoip` | routing |
| `loki` | `/srv/docker/loki` | analytics |
| `home-assistant-config` | `/srv/docker/home-assistant` | home |
| adguard-home (direct binds) | `/srv/docker/adguard/{conf,work}` | network |
| l4-port-manager (direct bind, ro) | `/srv/docker/caddy-l4` | routing |

These host directories must exist before `up -d` or the volume will fail to mount, **and ownership must match the container user** (`/srv/docker/caddy*` → uid 10000 for the panel's caddy image, `/srv/docker/caddy-manager` and `/srv/docker/loki` → uid 10001) — otherwise Caddy ACME fails with `mkdir /data/caddy: permission denied` (rsync `-aHAX` from the old location preserves ownership automatically):

```bash
sudo mkdir -p /srv/docker/caddy /srv/docker/caddy-config /srv/docker/caddy-geoip /srv/docker/caddy-manager /srv/docker/caddy-l4
sudo chown 10000:10000 /srv/docker/caddy /srv/docker/caddy-config /srv/docker/caddy-geoip
sudo chown 10001:10001 /srv/docker/caddy-manager /srv/docker/loki
```

### Shared Redis — DB map & persistence

The storage `redis` instance is shared by several stacks — logical DBs are de-facto owned per app, do not "clean up" without checking this map:

| DB | Owner | Content |
|----|-------|---------|
| db0 | cmnw app | `cmnw:cache:*` response cache (TTL ~6.6h) |
| db1 | osint/dma scrapers | `bull:*` queues + **`bull:osint.characters:<name>@<realm>` — 3.8M-key character-dedup index, ~5.6G, NO TTL (must survive restarts — losing it means rescraping)** |
| db2/db4 | GitLab | Rails cache + system cache |
| db3 | GitLab | sessions (`session:`) — flush = all GitLab users re-login |
| db10 | scrapers | small per-site dedup sets (vk, gibdd, yandex…) |

Persistence (since 2026-10-11): **AOF everysec only, RDB disabled** (`--save ""` in compose). RDB bgsave cadence on the 5.6G dataset was writing ~2.2 TB/day to nvme0. AOF rewrite still fires on 2× growth (~6 GB per event, infrequent). If redis is ever moved to its own disk or the dedup index grows further, the strategic fix is moving `bull:osint.characters:*` to a postgres lookup (the `characters` table in the `cmnw` DB already holds the same entities).

### Postgres & host write tuning (2026-10-11)

- **Postgres WAL**: `wal_compression = 'zstd'` (full page images compressed, −2–4× WAL volume) and `max_wal_size = '16GB'` — set via `ALTER SYSTEM`, persisted in `/mnt/postgres/postgresql.auto.conf`. max_wal_size applied live via reload; wal_compression (context superuser) is picked up by new sessions as pools reconnect. Rollback: `ALTER SYSTEM SET ...` + reload.
- **zram on the host**: `systemd-zram-generator` (pkg), config `/etc/systemd/zram-generator.conf` — `zram0`, `ram / 2` (15.6G), zstd, swap priority 100. The `/swap2.img` file stays as low-priority (pri −2) fallback with 0B used. Replaced a swapfile on nvme0 that was actively paged (~14 GB/day). To migrate swapped pages again after pressure: `swapoff /swap2.img && swapon /swap2.img` only when `MemAvailable ≥ 8G`.
- Replaced an earlier "15 jobs" count: prometheus now scrapes **16 jobs** — the list below plus **smartctl** (`smartctl-exporter:9633`, privileged container reading both NVMe drives, 60s polls). Key metrics for manual Grafana panels: `smartctl_device_percentage_used` (nvme0=36, nvme1=100 — the worn disk), `smartctl_device_critical_warning` (nvme1=0x04 until replaced), `smartctl_device_media_errors`, `smartctl_device_temperature{temperature_type="current"}`, `node_filesystem_avail_bytes/size_bytes{mountpoint="/|/mnt"}`.

### GitLab — canonical URL & runtime config (2026-10-11)

Canonical URL is **`https://gitlab.cmnw.ru`** (was `http://gitlab.cmnw.xyz`, which broke every web mutation: Omnibus nginx hardcoded `X-Forwarded-Proto: http` from its plain listener, so Rails' CSRF Origin check rejected all POSTs behind the TLS proxy with 422). TLS terminates at Caddy: panel proxy hosts `gitlab-ru` (`gitlab/git.cmnw.ru` → `gitlab:80`, cmnw.ru wildcard cert) and `gitlab-xyz` (`gitlab/git.cmnw.xyz` → same upstream, now a 302 redirect to `https://gitlab.cmnw.ru` via the panel `redirects` field with `from: "/*"` — `{uri}` placeholders are sanitized away, so it lands on root).

**The runtime source of truth is `/etc/gitlab/gitlab.rb` inside the container (named volume `git_config`), not this repo** — `GITLAB_OMNIBUS_CONFIG` in compose only seeds the metrics whitelist. A gitignored local mirror lives at `gitlab/config/gitlab.rb` (sync manually). After editing gitlab.rb: `docker exec gitlab gitlab-ctl reconfigure` (~1 min, puma restarts; no Portainer redeploy — compose doesn't change). Behind-proxy essentials that must stay in gitlab.rb: `external_url 'https://gitlab.cmnw.ru'` + `nginx['listen_port'] = 80` + `nginx['listen_https'] = false` + `nginx['proxy_set_headers'] = { "X-Forwarded-Proto" => "https", "X-Forwarded-Ssl" => "on" }` — drop the explicit headers and Rails goes back to seeing http.

SSH clone is independent of the URL: host `:2222` → socat `gitlab-ssh` → `gitlab:22` (bundled OpenSSH, `gitlab_shell_ssh_port = 2222`); the second `gitlab-sshd` daemon on container `:2222` is redundant and unused from outside. Panel API notes: `PUT /api/v1/proxy-hosts/{id}` only writes the SQLite DB — the push to Caddy is a separate `POST /api/v1/caddy/apply`; a working API token lives in the `cmnw-cert-sync` container env (`CPM_API_TOKEN`), the `/root/deploy/routing/stack.env` copy of it is stale.

### Prometheus & Loki Config — host files (since 2026-10-11)

Prometheus and Loki load their configs from **host bind mounts** under `/srv/docker/analytics/` — the inline `configs:` blocks are gone. Canonical copies live in the repo (`prometheus/prometheus.yml`, `loki/loki-config.yaml`); deploy flow: edit in repo → copy to `/srv/docker/analytics/` on the host → `POST http://128.0.0.255:9090/-/reload` (prometheus, `--web.enable-lifecycle` is on) or "Pull and redeploy" the analytics stack for loki. Absolute host paths are mandatory: Portainer runs compose inside its own container, so relative `file:` sources resolve to nonexistent paths. Bearer tokens for the MinIO and Home Assistant jobs are mounted as files (`/srv/docker/analytics/{minio,hass}.token`, mode 644 — the prometheus container runs as `nobody`) and referenced via `credentials_file`; the only remaining stack-env secret is `DATA_SOURCE_NAME` (postgres_exporter DSN). Grafana's `GF_*` settings are inlined in the compose (non-secret).

**All scrape targets are DNS names** over the stack's shared networks (`loki` bridge + `cmnw` external): container names for everything containerized, and `core.cmnw:8123` for Home Assistant — the host-network container is reached via the AGH rewrite `core.cmnw → 128.0.0.255` (docker embedded DNS forwards to AGH; do not delete that rewrite). Prometheus scrapes itself as `prometheus:9090`.

**16 jobs**: prometheus, node, postgres, caddy (`cmnw-caddy:2019`), rabbitmq, minio, home-assistant, gitlab (`/-/metrics`), gitlab-runner-i/ii (`:9252`), grafana, loki, promtail, redis, pgvector, smartctl.

**Auth**: MinIO scrape uses `authorization: Bearer ${MINIO_PROMETHEUS_TOKEN}` (generate with `mc admin prometheus generate <alias> cluster` against the MinIO root creds), Home Assistant uses `authorization: Bearer ${HASS_PROMETHEUS_TOKEN}` (HA long-lived access token; the HA `prometheus:` integration is enabled in `/srv/docker/home-assistant/configuration.yaml`, server-side, not in this repo). GitLab's `/-/metrics` is protected by `monitoring_whitelist` (RFC1918 + loopback), kept in sync between `gitlab.rb` in the volume (the live value) and `GITLAB_OMNIBUS_CONFIG` in `compose.gitlab.yaml` — see the GitLab section above. Both tokens live in the stack env (`../envs/analytics/.stack.env` + Portainer), never in the repo.

Prometheus TSDB retention: **720h (30d)**, matching Loki. Exporters for redis (`oliver006/redis_exporter`) and pgvector (second `postgres-exporter` pointed at the `lightrag` DB) run in the **storage** stack.

### Loki — 30-day retention, repo-managed config

Loki does **not** use the image's stock `local-config.yaml`. Its config is the repo file `loki/loki-config.yaml`, deployed to `/srv/docker/analytics/loki-config.yaml` and bind-mounted at `/etc/loki/local-config.yaml` (see "Prometheus & Loki Config"). Retention policy: **30 days, uniform** — enforced by the compactor (`retention_enabled: true`, `retention_period: 30d`) with `max_query_lookback: 30d` capping query windows. Deletion of already-ingested chunks lags by `retention_delete_delay` (default 2h) after the compactor marks them.

Data lives in the `loki` named volume (bind-mounted at `/srv/docker/loki`, owned by uid 10001 — the image's `loki` user). Historically the container ran with no volume and no retention, accumulating ~14.6 GB in its writable layer; that data was migrated to the bind mount and retention enabled on 2026-08-19 (moved from `/mnt/loki` to `/srv/docker/loki` on 2026-10-11).

### LightRAG — Graph-RAG in the oraculum stack (no Ollama)

`lightrag` in `compose.oraculum.yaml` is the [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG) server. It sits on the `oraculum` bridge network and reaches the storage stack over the host LAN IP `128.0.0.255`:

| LightRAG role | Engine | Service |
|---|---|---|
| Graph storage | PostgreSQL (`PGTableGraphStorage`, no AGE) | `pgvector` (storage stack, `128.0.0.255:5433`, `lightrag` DB) |
| Vector storage | PostgreSQL + pgvector | `pgvector` (same instance and DB) |
| KV + Doc-status | PostgreSQL | `pgvector` (same instance and DB) |

**Image — private fork, now built into the homelab registry.** The source is `gitlab.cmnw.ru/ai-platform/lightrag` (sigma wrapper app + vendored LightRAG engine; ADRs in `docs/adr/` of the fork); the GitLab CI (`ci/cmnw.yml`) builds the origin Dockerfile into `registry.cmnw.ru/ai-platform/lightrag` — dev branch bumps of `lightrag/_version.py` produce `v{version}` + rolling `:dev` (what the compose pins), `main` releases produce `v{version}` + `:latest`; the old `exp` branch and the GHCR push target are retired. Container listens on **8084** (hardcoded), host port stays 9621 via `:8084` mapping. The app has **no built-in auth** — the published port is LAN-only (`128.0.0.255`), keep it that way. API: `POST /create` → `POST /process` → `POST /track`, queries via `POST /read` (scope-based, multi-workspace, 429+`Retry-After` on GPU saturation). Workspaces are per-request (`workspace_id`), one worker per workspace, names lowercased.

**Oraculum live deploy path is `/root/deploy/oraculum` (SSH), not Portainer.** The last deploys (v1.5.7 rebuild 2026-10-11, hook/embedding update 2026-10-12) ran `docker compose -p oraculum -f compose.oraculum.yaml --env-file stack.env up -d lightrag` from that dir — the Portainer stack entry for oraculum is stale (still shows a pre-1.5.7 pin) and its clone dir was cleaned to just `stack.env` on 2026-10-12. **`--env-file stack.env` is mandatory**: the compose `environment:` block interpolates `${LIGHTRAG_PG_*}` from the compose process env, NOT from `env_file:` — without it the overrides go empty, the engine falls back to localhost:5432 and PG storages retry-loop. Keep the repo `compose.oraculum.yaml` image pin in sync with the tag you deploy.

**Config comes from the stack env (native var names); the compose `environment:` block only remaps `POSTGRES_*`.** All LightRAG vars — inference (`LLM_MODEL`/`QUERY_LLM_MODEL`/`LLM_BINDING_HOST/KEY`, `EMBEDDING_MODEL`/`DIM`/`EMBEDDING_BINDING_HOST/KEY`, `RERANK_*`), the binding types (`LLM_BINDING=openai`, `EMBEDDING_BINDING=openai`, `RERANK_BINDING=cohere`), the four PG storages, `REDIS_URL`/`RABBITMQ_URL`, `PORT=8084` (the gunicorn entrypoint otherwise listens on 9621 inside the container and the `9621:8084` mapping serves nothing), `WORKERS`, HNSW tuning, Loki and WebUI settings, auth — live in `../envs/oraculum/.stack.env` and reach the container verbatim via `env_file: stack.env`. The only thing the compose still overrides is the five-key `POSTGRES_HOST/PORT/USER/PASSWORD/DATABASE` → `LIGHTRAG_PG_*` remap on both lightrag services: the shared `POSTGRES_*` block in stack.env belongs to the oraculum Node apps (`:5432`/core) and one env file cannot hold two values — do not grow the block back. The stack runs TWO containers off the same image: `lightrag` (default CMD — the gunicorn API) and `lightrag-worker` (`python -m lightrag.worker`), the RabbitMQ consumer for the `lightrag.process` jobs that `POST /process` enqueues — without it indexing never completes. The containers are stateless (no volume): graph, vectors, KV and doc-status all live in postgres. **Do not let the repo compose and `/root/deploy/oraculum/compose.oraculum.yaml` drift — the 2026-10-12 Portainer redeploy from an out-of-date repo copy broke exactly this way.**

**Dedicated pgvector instance:** the `pgvector` service (image `pgvector/pgvector:0.8.6-pg17`, data at `/srv/docker/pgvector`) is separate from the shared `postgres` (vanilla `postgres:17.4` on :5432, untouched by LightRAG). The `lightrag` database and its user are created on first init from `LIGHTRAG_PG_*` in the storage stack env (`../envs/storage/.stack.env`) — keep those credentials identical in both stack envs. Vector index uses HNSW with cosine distance. Qdrant and neo4j are gone from the repo entirely; the LightRAG fork now stores its graph in postgres via `PGTableGraphStorage`.

**Loki log shipping — built into the fork, enabled in `../envs/oraculum/.stack.env`.** The fork ships a custom `LokiHandler` (`src/utils/loki_handler.py`) that batches Python `logging` records and POSTs them to `${LOKI_ENDPOINT}/loki/api/v1/push` with retry/backoff. It attaches to both `logging.root` (sigma app logs) and `logging.getLogger("lightrag")` (in-repo engine logs) — so entity extraction, KG merging, RAG queries and the API surface all land in Loki as one stream with `app=lightrag` labels plus per-request `user_id` / `workspace_id` context. The `env` label is canonicalized by `normalize_loki_env` (`src/utils/loki_common.py`): `dev/developement→development`, `prod→production`, `exp/experimental→experiments` — `LOKI_ENV=prod` ships as `env=production`, matching the other services. Exactly one gunicorn worker (flock-elected in `post_worker_init`, wired through `lightrag/api/gunicorn_config.py` → forwarded by `run_with_gunicorn.py`) attaches the handler and starts the hourly `MetricsService`; a v1.5.7 rebuild regression dropped those hooks from the forwarding whitelist and the container shipped nothing while looking healthy (fixed in `v1.5.7-exp.d5e8da4f`, 2026-10-12 — if Loki goes silent again, grep boot logs for `Metrics service started`). Reachability: lightrag hits Loki via `http://128.0.0.255:3100` (host LAN IP → analytics stack's published port). No compose change needed. The same sigma layer also writes a per-LLM-call audit table (`lightrag_llm_logs` in the pgvector DB, `[LLM_LOGS] enabled` in boot logs — was silently disabled before the `postgres_dsn` port fix).

**WebUI — vendored upstream SPA, served at `/webui/` on the same port.** The fork's classic `Dockerfile` (`D:\Projects\ai-platform\lightrag`) runs a multi-stage build that compiles `lightrag_webui/` (Vite + Bun) into `lightrag/api/webui/` and `src/app/main.py` mounts it via a `SmartStaticFiles` subclass that injects `window.__LIGHTRAG_CONFIG__ = {apiPrefix, webuiPrefix}` into `index.html` (same mechanism the upstream `lightrag.api.lightrag_server` uses). Root `/` redirects to `/webui/`. Reachable at `http://128.0.0.255:9621/webui/` from the LAN. Branding via `WEBUI_TITLE` / `WEBUI_DESCRIPTION` in the stack env.

**Upstream-compat routes** in `src/api/webui_routes.py` re-expose the upstream LightRAG HTTP surface the SPA expects (`/documents`, `/documents/upload`, `/documents/text`, `/documents/texts`, `/documents/track_status/{id}`, `/documents/paginated`, `/documents/status_counts`, `/documents/scan`, `/documents/reprocess_failed`, `/documents/cancel_pipeline`, `/documents/pipeline_status`, `/documents/clear_cache`, `/documents/delete_document`, `/documents/supported_file_types`, `/query`, `/query/stream`, `/auth-status`, `/login`, `/graph/entity/{exists,edit}`, `/graph/relation/edit`) and delegate to the fork's existing `/create`, `/process`, `/track`, `/read`, `/delete`, `/clear_cache` services. The SPA is single-tenant: `WEBUI_WORKSPACE` (default `default`) selects the fork workspace it operates against — other workspaces remain reachable via the fork's native API. Caveats: `graph/entity/{exists,edit}` and `graph/relation/edit` return 501 (PGTableGraphStorage does not implement per-entity mutation), `/documents/scan` returns 501 (fork has no INPUT_DIR scanner — upload via the SPA instead), `/login` verifies credentials when `AUTH_ACCOUNTS` is set (see Auth below).

**Auth — upstream-style JWT + API key, enabled via the stack env.** The fork mirrors upstream LightRAG auth (`src/api/auth.py`, reusing the vendored engine's `AuthHandler` and login rate limiter). `AUTH_ACCOUNTS` (comma-separated `user:password`, plaintext or `{bcrypt}`hash) turns on password login for the WebUI — 48 h HS256 JWTs signed with `TOKEN_SECRET`, auto-renewed via `X-New-Token`, 5 failed logins per IP+username per 5 min → 429 — and protects the whole API surface (SPA + native endpoints + `/workspaces`); the whitelist is `/login,/auth-status,/health,/docs,/redoc,/openapi.json`. Service-to-service callers authenticate with `LIGHTRAG_API_KEY` sent as `X-API-Key`: indexator reads it from the same stack env (`lightragConfig.apiKey`) and attaches it on `/create` and `/process` (v1.1.8+). With no `AUTH_ACCOUNTS` the fork runs open and hands out unsigned guest tokens. `AUTH_ACCOUNTS` without a non-default `TOKEN_SECRET` refuses to boot.

**Inference — all via OpenRouter, no local models:**
- **LLMs** — `LLM_MODEL` (extract, `deepseek/deepseek-v4-flash`) and `QUERY_LLM_MODEL` (answers, `deepseek/deepseek-v4-flash`) against `LLM_BINDING_HOST` (OpenRouter). Single model — text-only, 1M ctx, bounded reasoning overhead (~150 tokens), dodges the fork's broken reasoning-disable path on OpenRouter.
- **Embeddings** — `EMBEDDING_MODEL=qwen/qwen3-embedding-0.6b` via OpenRouter ($0.01/M tokens, 1024 dims, 32k context). Switched from `baai/bge-m3` because enriched Discord documents (message + author + channel + parent-context metadata) hit the 8k ceiling with HTTP 400 from bge-m3; qwen3-embedding-0.6b is the same price and same 1024-dim output, so no DB schema or vector-index rebuild needed beyond re-embedding the corpus. Deployed for real on 2026-10-12 (the AGENTS.md entry predates the actual switch by a day — until then every env still said bge-m3); the corpus was empty at switch time, so no re-embedding was needed. `EMBEDDING_DIM=1024` must match.
- **Rerank** — `RERANK_MODEL=cohere/rerank-4-fast` via `RERANK_BINDING_HOST` (OpenRouter).
- No Ollama, no HuggingFace downloads, no GPU — everything is API-routed.

---

## CI/CD Image Flow — local-first deploys

Images built by the repo's GitHub Actions workflows are available on the deploy host without a registry pull; GHCR (`ghcr.io/alexzedim/*`) is the backup/source of truth and deploys use the local copy.

- `compose.network.yaml`, `compose.oracle.yaml` and `compose.oraculum.yaml` set `pull_policy: if_not_present` on all `ghcr.io/alexzedim/*` services: deploy uses the local image and pulls from GHCR only if it's somehow missing locally. Without this, compose's default policy re-pulls `:latest` from GHCR on every deploy. Third-party images (lightrag, adguardhome etc.) keep the default policy.
- Stack webhooks (`pullimage`) and the "Re-pull image" GitOps toggle do nothing here; no stack uses GitOps webhooks/polling — deploys are manual ("Pull and redeploy" / "Update the stack"), which runs a plain `docker compose up -d`, so the file-level `pull_policy` is always in effect. Never check a "Re-pull image" option when you want the local copy.
- Quick health check: in Portainer's stack containers table, an image shown as a bare `sha256:…` fragment means the container was created from a registry pull; the image tag means it was created from the local build.
- `docker-prune` (in `compose.git.yaml`) is a nightly janitor (04:30 MSK, `DOCKER_PRUNE_CRON`) that prunes stopped containers, unused images, and build cache older than `DOCKER_PRUNE_RETENTION` (default `48h`). Images used by any container are never removed; volumes are never pruned. Logs: `docker logs docker-prune`.

---

## Stacks

| File | Services | Networks |
|------|----------|----------|
| `compose.storage.yaml` | PostgreSQL 17.4 (vanilla), Redis 7.4.3, MinIO, RabbitMQ 4.2.2, RabbitScout, pgvector 0.8.6 (LightRAG DB, :5433), redis-exporter, pgvector-exporter | `storage-network`, `cmnw` |
| `compose.routing.yaml` | Caddy (fuomag9 panel image), caddy-proxy-manager (web UI), docker-socket-proxy, l4-port-manager, cert-sync | `edge`, `cmnw`, `routing-internal`, `socket-proxy` |
| `compose.analytics.yaml` | Prometheus 3.15, Grafana 13.2, Loki 3.6.3, Promtail 3.6.3, postgres-exporter, node-exporter | `loki`, `cmnw` |
| `compose.home.yaml` | Home Assistant 2026.9.4 (LAN-only :8123, mDNS discovery) | `host` |
| `compose.git.yaml` | 6× GitHub Actions runners (`cmnw-github-runner-I..III`, `core-github-runner`, `oraculum-github-runner-I/II`), 2× GitLab runner managers (`gitlab-runner-I/II`, instance record "core-gitlab-runner", register `http://gitlab` on `cmnw`), docker-prune janitor | `runner-network`, `cmnw` (ext) |
| `compose.gitlab.yaml` | GitLab CE + gitlab-ssh (socat relay, host `:2222` → `gitlab:22`) | `cmnw` |
| `compose.oracle.yaml` | 6× scraper apps (oracle, -1d, -2bd, -3s, -4qr, -5se) joined to the vpn-oracle* gateways' netns (see "AdGuard — Home + VPN fleet") | — (inherits gateway netns) |
| `compose.oraculum.yaml` | indexator, oracular, archivum, gateway, lightrag, lightrag-worker | `oraculum` |
| `compose.ai.yaml` | GitHub MCP, Grafana MCP | `cmnw` |
| `compose.ai-platform.yaml` | ai-platform lab: ai-documents backend/worker/indexator/frontend (rolling `:dev` from `registry.cmnw.ru/ai-platform/*` — every push to a repo's `dev` branch produces a build, exp track retired 2026-10-18, ports 2050–2054 on 128.0.0.255) + wiki (docmost, :2054). Portainer Repository stack id 104, env = ../envs/ai-platform/.stack.env (71 pairs) | `cmnw` |
| `compose.control.yaml` | Portainer (TLS terminated by Caddy at `portainer.cmnw.ru`, upstream `portainer:9000` HTTP over `cmnw`; no local certs — the portainer volume `/data/certs` leftovers were removed 2026-10-11; host :9443 is no longer published) | `default`, `cmnw` |
| `compose.ai-local.yaml` | Ollama + Open WebUI with NVIDIA GPU passthrough | `ai-local-network` |
| `compose.network.yaml` | AdGuard Home (единственный DNS дома: plain `128.0.0.255:53` + DoT/DoQ-сервер `:853` для роутера, rewrites всех `*.cmnw`/`*.cmnw.ru`, allowed_clients = LAN, web UI `:3300`; upstreams = 3× DoH в load_balance (AdGuard private endpoint, dns.sb, quad9), fallback тоже DoH quad9, DNSSEC on — см. "AdGuard — Home + VPN fleet") + 6× vpn-oracle AdGuard VPN gateways (см. "AdGuard — Home + VPN fleet") | `cmnw` (ext), `oraculum_oraculum` (ext), default |

**Portainer 2.45 git-stack gotchas (learned 2026-10-12 on ai-platform, stack id 104):** there is NO stack-create API in CE 2.45 (`POST /api/stacks` → 405) — Repository stacks are created via the UI (Source = GitOps source `core`, env pasted in Advanced mode; the UI env persists to DB + `stack.env`). Every git deploy turns **file** bind sources into directories — both repo-relative (`./ai-platform/*.conf` → pre-created empty dirs the clone can't overwrite) and absolute host paths — so per-file mounts never come up; "Additional paths" in the Git settings are passed to compose as extra `-f` overlay files (breaks non-YAML files with "top-level object must be a mapping"). The frontend nginx config therefore lives in the **external volume `ai_platform_nginx_conf`** mounted ro at `/etc/nginx` — seeded once from the running image's stock tree + the repo's `ai-platform/web-nginx*.conf` (tmp container, `User: "0:0"` — the frontend image defaults to a non-root user); reseed the same way after changing the confs. `PUT /api/stacks/{id}/git/redeploy` with a full `Env` payload both deploys and persists the env to the stack DB record — never send `Env: []`.

---

## Key Conventions

- **File naming:** `compose.<category>.yaml`
- **Top of each file:** `name: '<category>'` (no `version:` field — it was dropped repo-wide as obsolete)
- **4-space indentation** in all YAML
- **Ports:** quote as strings (`'5432:5432'`), except where the existing file already uses unquoted — be consistent within each file
- **Comments:** in compose files, comments are allowed ONLY in the top-of-file header block and in `# ===...===` section banners above a service — no other inline or per-service comments anywhere else in the file; move all explanation into the header or a banner
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
# (http://128.0.0.255:3001) — it hot-reloads Caddy itself
docker logs -f cmnw-caddy
```

---

## Adding a New Service

1. Add to an existing `compose.<category>.yaml` or create a new one
2. Add env vars to **`.env.example`** (committed template) with a section header (`# ==== Section ====`) — non-secret defaults filled, secrets blank. Then copy the new vars into your local `.env` with real values.
3. For cross-stack connectivity, join the `cmnw` external network
4. For persistent data, add a named volume (use a bind mount to `/srv/docker/<name>` if the data needs a known host path — `/mnt/` is reserved for the postgres data dir on the legacy data disk)
5. If the service should be reachable via HTTPS, add a proxy host in the caddy-proxy-manager UI (or its REST API under `/api/v1/`)
6. Validate: `docker compose -f compose.<category>.yaml config`
7. Deploy: `docker compose -f compose.<category>.yaml up -d`
