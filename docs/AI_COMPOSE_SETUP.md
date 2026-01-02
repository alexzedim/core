# AI Compose Setup Documentation

## Overview

The `docker-compose.ai.yml` file contains all AI-related services including MCP (Model Context Protocol) servers and the production-ready Qdrant vector database.

## Services

### 1. GitHub MCP Server

**Purpose**: Provides GitHub integration capabilities for AI models and applications.

**Configuration**:
- **Image**: `ghcr.io/github/github-mcp-server`
- **Container Name**: `github-mcp-server`
- **Port**: `3001:3000`
- **Environment Variables**:
  - `MCP_SERVER_NAME`: github
  - `GITHUB_PERSONAL_ACCESS_TOKEN`: Set via `${GITHUB_TOKEN}` in `.env`

**Data Storage**:
- Volume: `mcp-github-data:/data`

**Health Check**: Enabled with 30s interval

### 2. Grafana MCP Server

**Purpose**: Provides Grafana dashboard integration for AI applications.

**Configuration**:
- **Image**: `mcp/grafana:latest`
- **Container Name**: `mcp-grafana`
- **Port**: `8001:8001`
- **Environment Variables**:
  - `GRAFANA_URL`: Set via `${GRAFANA_URL}` in `.env`
  - `GRAFANA_SERVICE_ACCOUNT_TOKEN`: Set via `${GRAFANA_SERVICE_ACCOUNT_TOKEN}` in `.env`

**Dependencies**: Depends on Qdrant service

**Health Check**: Enabled with 30s interval

### 3. Qdrant Vector Database

**Purpose**: Production-ready vector database for AI/ML applications with semantic search capabilities.

**Configuration**:
- **Image**: `qdrant/qdrant:latest`
- **Container Name**: `qdrant`
- **Ports**:
  - `6333:6333` - REST API
  - `6334:6334` - gRPC API

**Environment Variables**:
- `QDRANT_API_KEY`: API key for authentication (set via `${QDRANT_API_KEY}` in `.env`)
- `QDRANT_READ_ONLY_API_KEY`: Read-only key for metrics (set via `${QDRANT_READ_ONLY_API_KEY}` in `.env`)
- `QDRANT_TELEMETRY_DISABLED`: Disable telemetry (default: false)
- `QDRANT_LOG_LEVEL`: Logging level (default: info)

**Data Storage**:
- `qdrant_data:/qdrant/storage` - Main data storage
- Configuration file: `./qdrant/qdrant-config.yaml`
- Optional: Snapshots can be enabled for backup/recovery (see configuration)

**Health Check**: Enabled with 30s interval, 5 retries

**Networks**:
- `ai` - Internal AI network
- `cmnw` - External network for monitoring and reverse proxy

## Qdrant Configuration

### Production-Ready Features

The Qdrant configuration (`qdrant/qdrant-config.yaml`) includes:

1. **HTTP API Configuration**
   - Bind address: `0.0.0.0:6333`
   - Max payload size: 100MB
   - CORS enabled for all origins

2. **gRPC API Configuration**
   - Bind address: `0.0.0.0:6334`
   - Max message size: 100MB

3. **Storage Configuration**
   - Write-ahead log (WAL) enabled
   - WAL capacity: 1GB
   - Snapshots enabled with 10-minute interval

4. **Performance Tuning**
   - Max optimization threads: 4
   - HNSW configuration for vector search
   - Default vector size: 1536 (compatible with OpenAI embeddings)

5. **Security**
   - API key authentication
   - Read-only API key for monitoring
   - No new privileges security option

### Qdrant Data Paths

By default, Qdrant data is stored in:
- Data: `/opt/qdrant-data`

This path can be customized via environment variable:
- `QDRANT_DATA_PATH`

**Note**: Snapshots are disabled by default to reduce storage overhead. To enable snapshots for backup/recovery, uncomment the `qdrant_snapshots` volume in `docker-compose.ai.yml` and add the snapshots configuration to `qdrant/qdrant-config.yaml`.

## Networking

### Networks

1. **ai** (Internal)
   - Subnet: `172.25.0.0/16`
   - Gateway: `172.25.0.1`
   - Used for internal communication between AI services

2. **cmnw** (External)
   - External network for monitoring and reverse proxy integration
   - Allows Prometheus and Nginx to access Qdrant metrics

## Monitoring & Observability

### Prometheus Integration

Qdrant metrics are exposed at `http://qdrant:6333/metrics` and scraped by Prometheus with:
- Job name: `qdrant`
- Scrape interval: 15s
- Metrics path: `/metrics`

### Nginx Reverse Proxy

Two Nginx server blocks are configured for Qdrant:

1. **qdrant.cmnw.ru** (REST API)
   - SSL/TLS enabled
   - Basic authentication required
   - Proxy to `http://128.0.0.255:6333`
   - Includes `/health` and `/metrics` endpoints

2. **qdrant-grpc.cmnw.ru** (gRPC API)
   - SSL/TLS enabled with HTTP/2
   - Basic authentication required
   - Proxy to `grpc://128.0.0.255:6334`

### Grafana Dashboards

Qdrant metrics can be visualized in Grafana using:
- Data source: Prometheus
- Metrics: `qdrant_*` (all Qdrant metrics)

## Environment Variables

Add the following to your `.env` file:

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
QDRANT_SNAPSHOTS_PATH=/opt/qdrant-snapshots
```

## Starting the Services

### Start all AI services:
```bash
docker-compose -f docker-compose.ai.yml up -d
```

### Start specific service:
```bash
docker-compose -f docker-compose.ai.yml up -d qdrant
```

### View logs:
```bash
docker-compose -f docker-compose.ai.yml logs -f qdrant
```

### Stop services:
```bash
docker-compose -f docker-compose.ai.yml down
```

## Qdrant API Usage

### REST API Examples

**Health Check**:
```bash
curl -X GET "http://localhost:6333/health"
```

**Create Collection**:
```bash
curl -X PUT "http://localhost:6333/collections/my_collection" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 1536,
      "distance": "Cosine"
    }
  }'
```

**Insert Points**:
```bash
curl -X PUT "http://localhost:6333/collections/my_collection/points" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, ...],
        "payload": {"text": "example"}
      }
    ]
  }'
```

**Search**:
```bash
curl -X POST "http://localhost:6333/collections/my_collection/points/search" \
  -H "api-key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, ...],
    "limit": 10
  }'
```

### gRPC API

For gRPC clients, connect to `localhost:6334` with the API key in metadata.

## Backup & Recovery

### Create Snapshot

```bash
curl -X POST "http://localhost:6333/collections/my_collection/snapshots" \
  -H "api-key: your_api_key"
```

### List Snapshots

```bash
curl -X GET "http://localhost:6333/collections/my_collection/snapshots" \
  -H "api-key: your_api_key"
```

### Restore from Snapshot

Snapshots are stored in `/opt/qdrant-snapshots` and can be restored by:
1. Stopping the Qdrant container
2. Restoring the snapshot files
3. Restarting the container

## Performance Tuning

### For Large-Scale Deployments

1. **Increase WAL capacity**:
   ```yaml
   wal_capacity_mb: 2048  # 2GB
   ```

2. **Adjust HNSW parameters**:
   ```yaml
   m: 32  # More connections per node
   ef_construct: 400  # Better quality
   ef: 400  # Better search quality
   ```

3. **Enable memory mapping**:
   - Qdrant automatically uses mmap for large collections

4. **Resource allocation**:
   - Uncomment and adjust the `deploy.resources` section in `docker-compose.ai.yml`

## Troubleshooting

### Qdrant not starting

1. Check logs:
   ```bash
   docker-compose -f docker-compose.ai.yml logs qdrant
   ```

2. Verify data directory permissions:
   ```bash
   ls -la /opt/qdrant-data
   ```

3. Ensure ports are not in use:
   ```bash
   netstat -an | grep 6333
   netstat -an | grep 6334
   ```

### High memory usage

1. Check collection sizes:
   ```bash
   curl -X GET "http://localhost:6333/collections" \
     -H "api-key: your_api_key"
   ```

2. Reduce HNSW parameters if needed

3. Enable snapshots for cleanup

### Connection issues

1. Verify network connectivity:
   ```bash
   docker-compose -f docker-compose.ai.yml exec qdrant curl localhost:6333/health
   ```

2. Check API key configuration

3. Verify firewall rules for ports 6333 and 6334

## References

- [Qdrant Documentation](https://qdrant.tech/documentation/)
- [Qdrant Docker Setup Guide](https://dockerhosting.ru/blog/qdrant-v-docker-polnoe-rukovodstvo-po-ustanovke-i-nastrojke-vektornoj-bazy-dannyh/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [GitHub MCP Server](https://github.com/github/github-mcp-server)

## Migration Notes

### From Previous Setup

If you previously had MCP servers in other compose files:

1. **github-mcp-server** was moved from `docker-compose.github.yml`
2. **mcp-grafana** was moved from `docker-compose.analytics.yml`
3. Both services now run in the unified `docker-compose.ai.yml`

### Updating Existing Deployments

1. Stop old services:
   ```bash
   docker-compose -f docker-compose.github.yml down
   docker-compose -f docker-compose.analytics.yml down
   ```

2. Start new AI compose:
   ```bash
   docker-compose -f docker-compose.ai.yml up -d
   ```

3. Verify all services are running:
   ```bash
   docker-compose -f docker-compose.ai.yml ps
   ```
