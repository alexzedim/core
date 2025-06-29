<div align="center">
  <a href="https://cmnw.me/" target="blank">
    <img src="https://user-images.githubusercontent.com/907696/221422670-61897db8-4bbc-4436-969f-bdc5cf194275.svg" width="200" alt="CMNW Logo" />
  </a>

  <h1>CORE | CMNW </h1>

  <p>
    <img src="https://img.shields.io/badge/PostgreSQL-316192?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL">
    <img src="https://img.shields.io/badge/MongoDB-4EA94B?style=flat-square&logo=mongodb&logoColor=white" alt="MongoDB">    
    <img src="https://img.shields.io/badge/Redis-DC382D?style=flat-square&logo=redis&logoColor=white" alt="Redis">
    <img src="https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker">
    <img src="https://img.shields.io/badge/Portainer-13BEF6?style=flat-square&logo=portainer&logoColor=white" alt="Portainer">
    <img src="https://img.shields.io/badge/Traefik-24A1C1?style=flat-square&logo=traefik&logoColor=white" alt="Traefik">
    <img src="https://img.shields.io/badge/Home%20Assistant-41BDF5?style=flat-square&logo=home-assistant&logoColor=white" alt="Home Assistant">
    <img src="https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
    <img src="https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus">
    <img src="https://img.shields.io/badge/InfluxDB-22ADF6?style=flat-square&logo=influxdb&logoColor=white" alt="InfluxDB">
    <img src="https://img.shields.io/badge/MariaDB-003545?style=flat-square&logo=mariadb&logoColor=white" alt="MariaDB">
    <img src="https://img.shields.io/badge/RabbitMQ-FF6600?style=flat-square&logo=rabbitmq&logoColor=white" alt="RabbitMQ">
    <img src="https://img.shields.io/badge/MinIO-7D3EEF?style=flat-square&logo=minio&logoColor=white" alt="MinIO">
    <img src="https://img.shields.io/badge/Node--RED-8F0000?style=flat-square&logo=nodered&logoColor=white" alt="Node-RED">
    <img src="https://img.shields.io/badge/Loki-F7B93E?style=flat-square&logo=loki&logoColor=white" alt="Loki">
    <img src="https://img.shields.io/badge/MQTT-660066?style=flat-square&logo=mqtt&logoColor=white" alt="MQTT">
    <img src="https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=github-actions&logoColor=white" alt="GitHub Actions">
    <img src="https://img.shields.io/badge/VS%20Code-007ACC?style=flat-square&logo=visual-studio-code&logoColor=white" alt="VS Code">
    <img src="https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black" alt="Linux">
    <img src="https://img.shields.io/badge/Intel%20Xeon-0071C5?style=flat-square&logo=intel&logoColor=white" alt="Intel Xeon">
    <img src="https://img.shields.io/badge/RAID-10-00A651?style=flat-square&logo=raid&logoColor=white" alt="RAID 10">
    <img src="https://img.shields.io/badge/NVMe-000000?style=flat-square&logo=nvme&logoColor=white" alt="NVMe">
  </p>
</div>

---

## 🏠 Server Overview

**Hostname:** `core.cmnw`  
**Purpose:** Central infrastructure supporting all personal & home projects with 24/7 operations

### 🖥️ Hardware Specifications

- **CPU:** [Intel Xeon E5-2680v4](https://www.cpubenchmark.net/cpu.php?cpu=Intel+Xeon+E5-2680+v4+%40+2.40GHz&id=2779)
- **RAM:** 32GB DDR4
- **Storage:** RAID 10 SSD NVMe array
- **Network:** 1 Gbps SFP Ethernet
- **OS:** Linux (Docker-based containerization)

<div align="center">
  <img alt="System Monitoring" src="images/btop.png" width="100%"/>
  <p><em>docker container management interface</em></p>
  <img alt="Portainer" src="images/portainer.png" width="100%"/>
</div>

## 🏗️ Infrastructure Stack

This repository contains the complete infrastructure configuration for a self-hosted server running multiple services across different domains:

### 🔄 Reverse Proxy & Routing
- **Traefik v3.4** - Modern reverse proxy with automatic SSL certificate management
- **Let's Encrypt** integration for free SSL certificates
- **Docker provider** for automatic service discovery

### 🐳 Container Management
- **Portainer** - Web-based Docker container management interface
- **Docker Compose** - Multi-container application orchestration

### 📊 Monitoring & Analytics
- **Prometheus** - Metrics collection and storage
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **Promtail** - Log shipping agent
- **PostgreSQL Exporter** - Database metrics

### 🏠 Smart Home
- **Home Assistant** - Central home automation hub
- **Node-RED** - Visual programming for IoT flows
- **Zigbee2MQTT** - Zigbee device management
- **Z-Wave JS UI** - Z-Wave device control
- **Mosquitto** - MQTT message broker
- **InfluxDB** - Time-series database for sensor data

### 💾 Storage & Databases
- **PostgreSQL 17.4** - Primary relational database
- **Redis 7.4.3** - In-memory cache and message broker
- **RabbitMQ** - Message queue for job processing
- **MariaDB** - Additional database server
- **MinIO** - S3-compatible object storage

<div align="center">
  <p><em>requesting data in millions ops</em></p>
  <img alt="Pg" src="images/pg.png" width="100%"/>

  <img alt="Redis" src="images/redis.png" width="100%"/>
</div>

### 🔧 Development & CI/CD
- **Code Server** - Web-based VS Code environment
- **Portainer** - Docker container management
- **GitHub Runners** - Self-hosted CI/CD runners for:
  - `alexzedim/cmnw` repository
  - `alexzedim/oraculum` repository

## 📁 Project Structure

```
core/
├── docker-compose.analytics.yml    # Monitoring stack
├── docker-compose.example.yml      # Template/example configuration
├── docker-compose.github.yml       # CI/CD runners
├── docker-compose.home.yml         # Home automation services
├── docker-compose.jobs.yml         # Job queue services
├── docker-compose.maria.yml        # MariaDB database
├── docker-compose.routing.yml      # Traefik reverse proxy
├── docker-compose.s3.yml           # MinIO object storage
├── docker-compose.storage.yml      # PostgreSQL & Redis
├── traefik/                        # Traefik configuration
│   ├── traefik.yml                 # Main Traefik config
│   ├── dynamic.yml                 # Dynamic configuration
│   └── acme.json                   # SSL certificates
├── prometheus/                     # Prometheus configuration
│   └── prometheus.yml
├── loki/                          # Loki log aggregation
│   └── loki-config.yaml
└── mosquitto/                     # MQTT broker config
    └── mosquitto.conf
```

## 🚀 Services Overview

### Core Infrastructure
| Service | Port | Purpose |
|---------|------|---------|
| Traefik | 80, 443, 9000 | Reverse proxy & SSL termination |
| PostgreSQL | 5432 | Primary database |
| Redis | 6379 | Cache & message broker |
| MariaDB | 3306 | Additional database |
| MinIO | 9000, 9001 | S3-compatible storage |

### Home Automation
| Service | Port | Purpose |
|---------|------|---------|
| Home Assistant | Host | Home automation hub |
| Node-RED | 1880 | IoT flow programming |
| Zigbee2MQTT | 8080 | Zigbee device management |
| Z-Wave JS UI | 8091 | Z-Wave device control |
| Mosquitto | 1883 | MQTT message broker |
| InfluxDB | 8086 | Time-series data |

### Monitoring & Analytics
| Service | Port | Purpose |
|---------|------|---------|
| Grafana | 3000 | Dashboards & visualization |
| Prometheus | 9090 | Metrics collection |
| Loki | 3100 | Log aggregation |
| Promtail | - | Log shipping |
| PostgreSQL Exporter | 9187 | Database metrics |

### Development Tools
| Service | Port | Purpose |
|---------|------|---------|
| Code Server | 8443 | Web-based VS Code |
| Portainer | 9000 | Docker container management |
| GitHub Runners | - | CI/CD execution |
| RabbitMQ | 15672, 5672 | Message queue |

## 🔧 Configuration Management

### Environment Variables
Services are configured using environment files:
- `stack.env` - Shared environment variables
- Individual `.env` files for specific stacks

### Networking
- **Bridge networks** for service isolation
- **Host networking** for Home Assistant (hardware access)
- **Traefik labels** for automatic service discovery

### Storage
- **Named volumes** for persistent data
- **Bind mounts** for configuration files
- **RAID 10 SSD NVMe** for high-performance storage

## 🛠️ Deployment

### Prerequisites
- Docker & Docker Compose
- Linux host with Docker support
- Network access for Let's Encrypt certificates

### Quick Start
```bash
# Clone the repository
git clone <repository-url>
cd core

# Start individual stacks
docker-compose -f docker-compose.routing.yml up -d
docker-compose -f docker-compose.storage.yml up -d
docker-compose -f docker-compose.home.yml up -d
docker-compose -f docker-compose.analytics.yml up -d
# ... etc
```

### Service Management
```bash
# View running services
docker ps

# Check service logs
docker-compose -f docker-compose.home.yml logs -f

# Restart specific service
docker-compose -f docker-compose.home.yml restart home-assistant
```

## 📈 Monitoring & Maintenance

### Health Checks
- All services include health check configurations
- Prometheus metrics for system monitoring
- Grafana dashboards for visualization

### Backup Strategy
- Database volumes are persisted
- Configuration files are version controlled
- Regular backups of critical data

### Security
- Traefik handles SSL/TLS termination
- Services run with minimal privileges
- Network isolation between stacks
- Environment-based secrets management

## 📝 Notes

- All services are configured for 24/7 operation
- Automatic restart policies ensure high availability
- Resource limits are configured for optimal performance
- The server supports multiple personal projects simultaneously
- RAID 10 configuration provides both performance and redundancy

---

**Maintained by:** alexzedim
