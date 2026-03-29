# AGENTS.md — Core Infrastructure Repository

## Overview

This repository (`core`) contains the complete infrastructure configuration for a self-hosted server (`core.cmnw`) running **Docker-based containerized services** including PostgreSQL, Redis, RabbitMQ, MinIO, Nginx reverse proxy, Home Assistant, Prometheus/Grafana, Ollama, and more.

**This is infrastructure-as-code, not application source code.** There are no tests, no linting tools, and no build commands in the traditional sense.

---

## 1. Build / Deploy / Test Commands

### Docker Compose Management

```bash
# Start a stack
docker-compose -f docker-compose.<stack>.yml up -d

# Stop a stack
docker-compose -f docker-compose.<stack>.yml down

# Restart a specific service
docker-compose -f docker-compose.storage.yml restart postgres

# View logs (all services in stack)
docker-compose -f docker-compose.storage.yml logs

# View logs for specific service with follow
docker-compose -f docker-compose.analytics.yml logs -f prometheus

# Rebuild and restart a service
docker-compose -f docker-compose.<stack>.yml up -d --build <service>

# Pull latest images for all services in a stack
docker-compose -f docker-compose.<stack>.yml pull

# Validate compose file syntax
docker-compose -f docker-compose.<stack>.yml config

# List running containers across all compose files
docker ps

# Remove stopped containers and dangling images
docker system prune -f
```

### Service Health Checks

```bash
# Inspect service health status
docker inspect --format='{{json .State.Health}}' <container_name>

# Check if PostgreSQL is ready
docker exec postgres pg_isready -U postgres

# Check Redis connectivity
docker exec redis redis-cli -a <password> ping
```

### Backup Commands

```bash
# Backup PostgreSQL database
docker exec postgres pg_dump -U postgres cmnw > backup_$(date +%Y%m%d).sql

# Backup Redis data
docker exec redis redis-cli -a <password> SAVE

# Backup MinIO data (using mc client)
docker exec minio mc alias set local http://localhost:9000 <root_user> <root_password>
docker exec minio mc mirror local/cmnw-data /backups/
```

### Network & Debugging

```bash
# List all Docker networks
docker network ls

# Inspect a specific network
docker network inspect storage-network

# View resource usage
docker stats

# Shell into a container
docker exec -it <container_name> /bin/sh
```

---

## 2. Code Style Guidelines

### YAML — Docker Compose Files

- **File naming:** `docker-compose.<category>.yml` (e.g., `docker-compose.storage.yml`, `docker-compose.analytics.yml`)
- **Version:** Always use `version: '3.8'`
- **Name field:** Include `name: '<category>'` at the top of each compose file
- **Indentation:** 4 spaces (no tabs)
- **Environment variables:** Use `${VAR_NAME}` syntax; do NOT hardcode values
- **Ports:** Always quote port mappings as strings: `'5432:5432'` not `5432:5432`
- **Volumes:** Use named volumes for persistent data; use bind mounts for config files
- **Networks:** Use descriptive bridge network names (e.g., `storage-network`, `analytics-network`)
- **Restart policy:** Use `restart: always` for long-running services
- **Container naming:** Use `container_name:` for services that should have fixed names (avoids auto-generated names)
- **Health checks:** Always define `healthcheck:` for database services (postgres, redis, rabbitmq)
- **Comments:** Use `#` for section headers and important notes; keep them concise

**Example structure:**
```yaml
name: 'storage'
version: '3.8'
services:
  postgres:
    image: postgres:17.4
    container_name: postgres
    restart: always
    networks:
      - storage-network
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - '5432:5432'
    volumes:
      - postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  storage-network:
    driver: bridge

volumes:
  postgres:
    driver: local
```

### Environment Files (.env)

- **Location:** `.env` in the repository root
- **Secrets:** Never commit actual secret values; use empty placeholders: `POSTGRES_PASSWORD=`
- **Comments:** Use section headers with `====` dividers:
  ```bash
  # ============================================================================
  # PostgreSQL Database Configuration (storage.yml)
  # ============================================================================
  ```
- **Organization:** Group variables by service/stack with clear section headers

### Nginx Configuration

- **File location:** `nginx/nginx.conf` (main) and `nginx/conf.d/` (per-site)
- **Worker processes:** `worker_processes auto;`
- **Worker connections:** `worker_connections 10240;`
- **SSL protocols:** TLSv1.2 and TLSv1.3 only
- **SSL ciphers:** Use modern cipher suites only
- **HTTP/2:** Enable with `http2 on;` on listen directives
- **HSTS header:** Always include `Strict-Transport-Security` on SSL virtual hosts
- **Upstream keepalive:** `keepalive 32;` for upstream connections
- **Proxy headers:** Always set all standard proxy headers:
  ```nginx
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto https;
  proxy_set_header X-Forwarded-Host $host;
  proxy_set_header X-Forwarded-Port 443;
  ```
- **WebSocket support:** Include upgrade headers when proxying WebSocket connections
- **SSL certificates:** Store in `/etc/nginx/.certs/` inside containers

### Prometheus Configuration (prometheus.yml)

- **Indentation:** 4 spaces
- **Scrape intervals:** 15s for standard, 30s for expensive targets (databases)
- **Metrics path:** Default to `/metrics`
- **Job naming:** Use descriptive job names matching the service name

### General Conventions

- **No trailing whitespace** on any line
- **No hardcoded IP addresses** — use service names as hostnames (Docker DNS)
- **Consistent naming:** Use `kebab-case` for all resource names (networks, volumes, services)
- **External networks:** If a service needs to join an existing network, declare it with `external: true`
- **Resource limits:** Always set `deploy.resources.limits` for production services (memory, CPU)
- **Read-only volumes:** Use `:ro` suffix for config volumes that don't need write access
- **Labeling:** Add descriptive labels to services for documentation and tooling

### What NOT to Do

- Do NOT hardcode passwords or secrets in compose files — use `${VAR}` or environment files
- Do NOT use `privileged: true` unless absolutely necessary
- Do NOT use `host` network mode unless required for hardware access (e.g., Home Assistant)
- Do NOT leave ports exposed to all interfaces (`0.0.0.0`) unless required
- Do NOT commit `.env` files with actual secret values to version control
- Do NOT use `:latest` tags for images — use specific version tags (e.g., `postgres:17.4`)

---

## 3. Repository Structure

```
core/
├── docker-compose.storage.yml    # PostgreSQL, Redis, MinIO, RabbitMQ
├── docker-compose.routing.yml    # Nginx reverse proxy with SSL
├── docker-compose.analytics.yml  # Prometheus, Grafana, Loki, Promtail
├── docker-compose.home.yml       # Home Assistant, Node-RED, Mosquitto, InfluxDB
├── docker-compose.git.yml        # GitHub self-hosted runners
├── docker-compose.gitlab.yml    # GitLab CE
├── docker-compose.ai.yml         # Ollama, Open WebUI, Qdrant, MCP servers
├── docker-compose.control.yml    # Portainer
├── docker-compose.example.yml    # Comprehensive template/documentation
├── docker-compose.ai-local.yml  # Local AI with GPU support
├── .env                          # Environment variables (secrets)
├── nginx/
│   ├── nginx.conf                # Main nginx config
│   └── conf.d/                   # Per-site configurations
├── prometheus/
│   └── prometheus.yml            # Prometheus scrape configs
├── loki/
│   └── loki-config.yaml          # Loki retention config
└── qdrant/
    └── config/config.yaml        # Qdrant vector DB config
```

---

## 4. Adding a New Service

1. Create a new `docker-compose.<category>.yml` or add to an existing stack
2. Follow the YAML structure and conventions above
3. Add environment variables to `.env` with a section header
4. If the service needs network access, add it to an existing network or create a new one
5. If the service needs persistent storage, add a named volume
6. Validate: `docker-compose -f docker-compose.<category>.yml config`
7. Start: `docker-compose -f docker-compose.<category>.yml up -d`
8. Check logs: `docker-compose -f docker-compose.<category>.yml logs -f <service>`
