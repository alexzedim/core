# AI Services Migration Summary

## Overview

Successfully migrated all MCP (Model Context Protocol) servers and implemented production-ready Qdrant vector database into a unified `docker-compose.ai.yml` file.

## Changes Made

### 1. New Files Created

#### `docker-compose.ai.yml`
- **Purpose**: Unified compose file for all AI services
- **Services**:
  - `github-mcp-server`: GitHub integration for AI models
  - `mcp-grafana`: Grafana dashboard integration
  - `qdrant`: Production-ready vector database
- **Networks**: External `cmnw` network (shared with monitoring and reverse proxy)
- **Volumes**: Persistent storage for all services

#### `qdrant/qdrant-config.yaml`
- **Purpose**: Production-ready Qdrant configuration
- **Features**:
  - HTTP API on port 6333
  - gRPC API on port 6334
  - Write-ahead log (WAL) enabled
  - HNSW vector search optimization
  - CORS enabled for API access
  - API key authentication
  - Optional snapshots for backup/recovery (disabled by default)

#### `docs/AI_COMPOSE_SETUP.md`
- Comprehensive documentation for AI compose setup
- Service configurations and usage examples
- Qdrant API usage examples
- Backup and recovery procedures
- Performance tuning guidelines
- Troubleshooting guide

#### `qdrant/.env.example`
- Environment variables template
- Configuration options for all services
- Performance tuning parameters
- Security settings

### 2. Modified Files

#### `docker-compose.analytics.yml`
**Removed**:
- `mcp-grafana` service (moved to `docker-compose.ai.yml`)

**Added**:
- Qdrant scrape configuration in Prometheus config
  - Job name: `qdrant`
  - Scrape interval: 15s
  - Metrics path: `/metrics`

#### `docker-compose.github.yml`
**Removed**:
- `github-mcp-server` service (moved to `docker-compose.ai.yml`)
- `mcp-github-data` volume (moved to `docker-compose.ai.yml`)

#### `prometheus/prometheus.yml`
**Added**:
- Qdrant metrics scrape configuration
  - Target: `qdrant:6333`
  - Scrape interval: 15s
  - Metrics path: `/metrics`

#### `nginx/conf.d/default.conf`
**Added**:
- `qdrant.cmnw.ru` server block (REST API)
  - SSL/TLS enabled
  - Basic authentication required
  - Proxy to `http://128.0.0.255:6333`
  - Health check and metrics endpoints

- `qdrant-grpc.cmnw.ru` server block (gRPC API)
  - SSL/TLS with HTTP/2 enabled
  - Basic authentication required
  - gRPC proxy to `grpc://128.0.0.255:6334`

## Service Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    docker-compose.ai.yml                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ github-mcp-server│  │  mcp-grafana     │                 │
│  │  Port: 3001      │  │  Port: 8001      │                 │
│  └──────────────────┘  └──────────────────┘                 │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Qdrant Vector Database                      │   │
│  │  REST API: 6333  │  gRPC API: 6334                   │   │
│  │  Storage: /opt/qdrant-data                           │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  Network: cmnw (external)                                    │
│  - Shared with Prometheus, Nginx, and other services        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
         │                          │
         ▼                          ▼
    ┌─────────────┐         ┌──────────────┐
    │  Prometheus │         │    Nginx     │
    │  (Metrics)  │         │ (Reverse Proxy)
    └─────────────┘         └──────────────┘
         │                          │
         ▼                          ▼
    ┌─────────────┐         ┌──────────────┐
    │  Grafana    │         │  Clients     │
    │ (Dashboard) │         │ (via HTTPS)  │
    └─────────────┘         └──────────────┘
```

## Monitoring & Observability

### Prometheus Integration
- **Qdrant metrics endpoint**: `http://qdrant:6333/metrics`
- **Scrape interval**: 15 seconds
- **Metrics available**: All Qdrant performance and operational metrics

### Nginx Reverse Proxy
- **REST API**: `https://qdrant.cmnw.ru` (port 443)
- **gRPC API**: `https://qdrant-grpc.cmnw.ru` (port 443)
- **Authentication**: Basic auth via `.htpasswd`
- **SSL/TLS**: Let's Encrypt certificates

### Grafana Dashboards
- Qdrant metrics can be visualized using Prometheus data source
- Create custom dashboards for vector database monitoring

## Environment Variables Required

Add to your `.env` file:

```bash
# GitHub MCP Server
GITHUB_TOKEN=your_github_personal_access_token

# Grafana MCP Server
GRAFANA_URL=https://grafana.cmnw.ru
GRAFANA_SERVICE_ACCOUNT_TOKEN=your_grafana_service_account_token

# Qdrant Vector Database
QDRANT_API_KEY=your_secure_api_key_here
QDRANT_READ_ONLY_API_KEY=your_secure_read_only_key_here
QDRANT_TELEMETRY_DISABLED=false
QDRANT_LOG_LEVEL=info
QDRANT_DATA_PATH=/opt/qdrant-data
```

## Deployment Instructions

### 1. Prepare Environment
```bash
# Create data directory
mkdir -p /opt/qdrant-data

# Set proper permissions
chmod 755 /opt/qdrant-data
```

### 2. Update Configuration
```bash
# Copy environment template
cp qdrant/.env.example .env

# Edit .env with your values
nano .env
```

### 3. Start Services
```bash
# Start AI services
docker-compose -f docker-compose.ai.yml up -d

# Verify services are running
docker-compose -f docker-compose.ai.yml ps

# Check logs
docker-compose -f docker-compose.ai.yml logs -f
```

### 4. Verify Connectivity
```bash
# Test Qdrant REST API
curl -X GET "http://localhost:6333/health"

# Test Prometheus scraping
curl -X GET "http://localhost:9090/api/v1/targets"

# Test Nginx reverse proxy
curl -X GET "https://qdrant.cmnw.ru/health" \
  -u username:password \
  -k  # Skip SSL verification for testing
```

## Migration Checklist

- [x] Create `docker-compose.ai.yml` with all MCP servers
- [x] Implement production-ready Qdrant configuration
- [x] Remove MCP servers from original compose files
- [x] Update Prometheus configuration for Qdrant metrics
- [x] Add Nginx reverse proxy configuration
- [x] Create comprehensive documentation
- [x] Create environment variables template
- [ ] Update DNS records for `qdrant.cmnw.ru` and `qdrant-grpc.cmnw.ru`
- [ ] Configure SSL certificates (Let's Encrypt)
- [ ] Test all services in production environment
- [ ] Update deployment documentation
- [ ] Backup existing data before migration

## Rollback Plan

If issues occur:

1. **Stop new services**:
   ```bash
   docker-compose -f docker-compose.ai.yml down
   ```

2. **Restore old services**:
   ```bash
   docker-compose -f docker-compose.github.yml up -d
   docker-compose -f docker-compose.analytics.yml up -d
   ```


## Performance Characteristics

### Qdrant Vector Database
- **Vector Size**: 1536 (OpenAI compatible)
- **Distance Metric**: Cosine similarity
- **Index Type**: HNSW (Hierarchical Navigable Small World)
- **Max Payload Size**: 100MB
- **Max Message Size (gRPC)**: 100MB
- **WAL Capacity**: 1GB

### Resource Usage
- **Memory**: Depends on collection size (no limits set)
- **CPU**: Up to 4 threads for optimization
- **Storage**: Persistent volumes for data and snapshots

## Security Considerations

1. **API Authentication**
   - All Qdrant API calls require API key
   - Read-only key for monitoring/metrics

2. **Network Security**
    - External `cmnw` network for all service communication
    - Shared with Prometheus, Nginx, and other infrastructure services
    - Nginx reverse proxy with SSL/TLS

3. **Access Control**
   - Basic authentication on Nginx reverse proxy
   - API key authentication on Qdrant
   - Firewall rules for port access

4. **Data Protection**
    - Persistent volumes for data durability
    - Write-ahead log for crash recovery
    - Optional snapshots for backup (can be enabled if needed)

## Troubleshooting

### Services won't start
1. Check Docker daemon is running
2. Verify port availability (6333, 6334, 3001, 8001)
3. Check logs: `docker-compose -f docker-compose.ai.yml logs`

### Qdrant connection issues
1. Verify container is running: `docker ps | grep qdrant`
2. Test health endpoint: `curl http://localhost:6333/health`
3. Check API key configuration

### Prometheus not scraping Qdrant
1. Verify Qdrant is on `cmnw` network
2. Check Prometheus config: `docker-compose -f docker-compose.analytics.yml logs prometheus`
3. Test connectivity: `docker exec prometheus curl http://qdrant:6333/metrics`

### Nginx reverse proxy issues
1. Check SSL certificates are valid
2. Verify `.htpasswd` file exists
3. Test proxy: `curl -v https://qdrant.cmnw.ru/health`

## References

- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Qdrant Docker Setup Guide](https://dockerhosting.ru/blog/qdrant-v-docker-polnoe-rukovodstvo-po-ustanovke-i-nastrojke-vektornoj-bazy-dannyh/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Nginx Documentation](https://nginx.org/en/docs/)

## Support & Questions

For issues or questions:
1. Check the comprehensive documentation in `docs/AI_COMPOSE_SETUP.md`
2. Review Qdrant logs: `docker-compose -f docker-compose.ai.yml logs qdrant`
3. Check Prometheus targets: `https://prometheus.cmnw.ru/targets`
4. Review Grafana dashboards for metrics visualization
