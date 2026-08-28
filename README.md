<div align="center">
  <a href="https://cmnw.me/" target="blank">
    <img src="https://user-images.githubusercontent.com/907696/221422670-61897db8-4bbc-4436-969f-bdc5cf194275.svg" width="200" alt="CMNW Logo" />
  </a>

  <h1>CORE | CMNW</h1>

  <p>Infrastructure-as-code for a self-hosted server running containerized services across storage, routing, analytics, home automation, AI and CI/CD — orchestrated with Docker Compose behind an Nginx reverse proxy.</p>
</div>

---

## 🏠 Server Overview

### 🖥️ Hardware

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

## ⚡ Tech Stack

<div align="center">

#### 🔄 Edge & Network

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/nginx.svg" alt="Nginx logo" width="48"/><br/>Nginx</td>
    <td valign="bottom"><img src="./icons/adguard.svg" alt="AdGuard logo" width="48"/><br/>AdGuard</td>
</tr>
</table>
</div>

<div align="center">

#### 💾 Data & Storage

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/postgresql.svg" alt="PostgreSQL logo" width="48"/><br/>PostgreSQL</td>
    <td valign="bottom"><img src="./icons/postgresql.svg" alt="pgvector logo" width="48"/><br/>pgvector</td>
    <td valign="bottom"><img src="./icons/redis.svg" alt="Redis logo" width="48"/><br/>Redis</td>
    <td valign="bottom"><img src="./icons/rabbitmq.svg" alt="RabbitMQ logo" width="48"/><br/>RabbitMQ</td>
    <td valign="bottom"><img src="./icons/minio.svg" alt="MinIO logo" width="48"/><br/>MinIO</td>
    <td valign="bottom"><img src="./icons/influxdb.svg" alt="InfluxDB logo" width="48"/><br/>InfluxDB</td>
</tr>
</table>
</div>

<div align="center">

#### 📊 Monitoring & Observability

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/prometheus.svg" alt="Prometheus logo" width="48"/><br/>Prometheus</td>
    <td valign="bottom"><img src="./icons/grafana.svg" alt="Grafana logo" width="48"/><br/>Grafana</td>
    <td valign="bottom"><img src="./icons/loki.svg" alt="Loki logo" width="48"/><br/>Loki</td>
</tr>
</table>
</div>

<div align="center">

#### 🏠 Smart Home

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/homeassistant.svg" alt="Home Assistant logo" width="48"/><br/>Home Assistant</td>
    <td valign="bottom"><img src="./icons/nodered.svg" alt="Node-RED logo" width="48"/><br/>Node-RED</td>
    <td valign="bottom"><img src="./icons/zigbee.svg" alt="Zigbee2MQTT logo" width="48"/><br/>Zigbee2MQTT</td>
    <td valign="bottom"><img src="./icons/zwave-js.svg" alt="Z-Wave JS UI logo" width="48"/><br/>Z-Wave JS UI</td>
    <td valign="bottom"><img src="./icons/mqtt.svg" alt="Mosquitto logo" width="48"/><br/>Mosquitto</td>
</tr>
</table>
</div>

<div align="center">

#### 🤖 AI & RAG

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/lightrag.svg" alt="LightRAG logo" width="48"/><br/>LightRAG</td>
    <td valign="bottom"><img src="./icons/openrouter.svg" alt="OpenRouter logo" width="48"/><br/>OpenRouter</td>
    <td valign="bottom"><img src="./icons/ollama.svg" alt="Ollama logo" width="48"/><br/>Ollama</td>
    <td valign="bottom"><img src="./icons/openwebui.png" alt="Open WebUI logo" width="48"/><br/>Open WebUI</td>
    <td valign="bottom"><img src="./icons/modelcontextprotocol.svg" alt="MCP logo" width="48"/><br/>MCP</td>
</tr>
</table>
</div>

<div align="center">

#### ⚙️ Runtime

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/nodejs.svg" alt="Node.js logo" width="48"/><br/>Node.js</td>
    <td valign="bottom"><img src="./icons/typescript.svg" alt="TypeScript logo" width="48"/><br/>TypeScript</td>
    <td valign="bottom"><img src="./icons/python.svg" alt="Python logo" width="48"/><br/>Python</td>
</tr>
</table>
</div>

<div align="center">

#### 🔧 CI/CD & DevOps

</div>
<div align="center">
<table align="center">
<tr align="center">
    <td valign="bottom"><img src="./icons/docker.svg" alt="Docker logo" width="48"/><br/>Docker</td>
    <td valign="bottom"><img src="./icons/gitlab.svg" alt="GitLab logo" width="48"/><br/>GitLab</td>
    <td valign="bottom"><img src="./icons/github-actions.svg" alt="GitHub Actions logo" width="48"/><br/>GitHub Actions</td>
    <td valign="bottom"><img src="./icons/portainer.svg" alt="Portainer logo" width="48"/><br/>Portainer</td>
    <td valign="bottom"><img src="./icons/ubuntu.svg" alt="Ubuntu logo" width="48"/><br/>Ubuntu</td>
</tr>
</table>
</div>

## 🧱 Compose Stacks

| Stack | Services | Networks |
|-------|----------|----------|
| `docker-compose.storage.yml` | PostgreSQL 17.4, Redis 7.4.3, MinIO, RabbitMQ 4.2.2, RabbitScout, pgvector 0.8.6 (LightRAG DB) | `storage-network`, `cmnw` |
| `docker-compose.routing.yml` | Nginx 1.27, Nginx-UI, Nginx Prometheus Exporter | `edge`, `cmnw` |
| `docker-compose.analytics.yml` | Prometheus, Promtail, Loki 3.6.3, Grafana, Node Exporter, Postgres Exporter | `loki`, `cmnw` |
| `docker-compose.home.yml` | Home Assistant, Mosquitto, Node-RED, Zigbee2MQTT, Z-Wave JS UI, InfluxDB 2 | `host` (HA), `traefik` (ext) |
| `docker-compose.git.yml` | 5× GitHub Actions runners, docker-prune janitor | `runner-network` |
| `docker-compose.gitlab.yml` | GitLab CE 19.0.1 | `cmnw` |
| `docker-compose.oracle.yml` | 6× vpn-oracle AdGuard VPN gateways + `oracle` / `-1d` / `-2bd` / `-3s` / `-4qr` / `-5se` | `oraculum`, `cmnw` |
| `docker-compose.oraculum.yml` | indexator, oracular, archivum, gateway, LightRAG | `oraculum` |
| `docker-compose.ai.yml` | GitHub MCP, Grafana MCP, Open WebUI | `cmnw` |
| `docker-compose.control.yml` | Portainer CE | `traefik` (ext) |
| `docker-compose.ai-local.yml` | Ollama + Open WebUI (NVIDIA GPU passthrough) | `ai-local-network` |

<div align="center">
  <p><em>requesting data in millions ops</em></p>
  <img alt="Pg" src="images/pg.png" width="100%"/>
  <img alt="Redis" src="images/redis.png" width="100%"/>
</div>

## ✨ Highlights

- **Multi-domain TLS routing** — SSL-terminated reverse proxy serving `cmnw.me`, `cmnw.xyz`, `cmnw.ru`
- **Full observability stack** — Prometheus metrics, Grafana dashboards, Loki log aggregation with 30-day retention
- **Smart home automation** — Home Assistant hub with Zigbee and Z-Wave device meshes over MQTT
- **Graph-RAG platform** — LightRAG (private fork) with graph + vectors in PostgreSQL/pgvector, inference routed via OpenRouter
- **Egress VPN fleet** — six AdGuard VPN gateways powering the oracle farm
- **CI/CD pipeline** — self-hosted GitHub Actions runners building straight into the local Docker daemon
- **Infrastructure as code** — every service defined in version-controlled Docker Compose files, deployed via Portainer

## 📁 Project Structure

```
core/
├── docker-compose.storage.yml      # PostgreSQL, Redis, MinIO, RabbitMQ, pgvector
├── docker-compose.routing.yml      # Nginx, Nginx-UI, metrics exporter
├── docker-compose.analytics.yml    # Prometheus, Grafana, Loki, Promtail
├── docker-compose.home.yml         # Home Assistant, Node-RED, Zigbee2MQTT, Z-Wave, InfluxDB
├── docker-compose.git.yml          # GitHub Actions runners (5×), docker-prune
├── docker-compose.gitlab.yml       # GitLab CE
├── docker-compose.oracle.yml       # AdGuard VPN gateways + oracle apps
├── docker-compose.oraculum.yml     # indexator, oracular, archivum, gateway, LightRAG
├── docker-compose.ai.yml           # GitHub MCP, Grafana MCP, Open WebUI
├── docker-compose.control.yml      # Portainer
├── docker-compose.ai-local.yml     # Ollama + Open WebUI (GPU passthrough)
├── docker-compose.example.yml      # template / documentation
├── nginx/                          # reference nginx configs
├── prometheus/                     # reference prometheus config
├── loki/                           # reference loki config
├── mosquitto/                      # mosquitto config
├── icons/                          # README icon assets
└── images/                         # README screenshots
```

---

**Maintained by:** [alexzedim](https://github.com/alexzedim) · operational conventions in [AGENTS.md](./AGENTS.md)
