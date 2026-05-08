<div align="center">
  <a href="https://cmnw.me/" target="blank">
    <img src="https://user-images.githubusercontent.com/907696/221422670-61897db8-4bbc-4436-969f-bdc5cf194275.svg" width="200" alt="CMNW Logo" />
  </a>

  <h1>CORE | CMNW</h1>

  <p>
    <img src="https://img.shields.io/badge/PostgreSQL-316192?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL">
    <img src="https://img.shields.io/badge/Redis-DC382D?style=flat-square&logo=redis&logoColor=white" alt="Redis">
    <img src="https://img.shields.io/badge/RabbitMQ-FF6600?style=flat-square&logo=rabbitmq&logoColor=white" alt="RabbitMQ">
    <img src="https://img.shields.io/badge/MinIO-7D3EEF?style=flat-square&logo=minio&logoColor=white" alt="MinIO">
    <img src="https://img.shields.io/badge/Nginx-009639?style=flat-square&logo=nginx&logoColor=white" alt="Nginx">
    <img src="https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker">
    <img src="https://img.shields.io/badge/Portainer-13BEF6?style=flat-square&logo=portainer&logoColor=white" alt="Portainer">
    <img src="https://img.shields.io/badge/Home%20Assistant-41BDF5?style=flat-square&logo=home-assistant&logoColor=white" alt="Home Assistant">
    <img src="https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white" alt="Grafana">
    <img src="https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus">
    <img src="https://img.shields.io/badge/InfluxDB-22ADF6?style=flat-square&logo=influxdb&logoColor=white" alt="InfluxDB">
    <img src="https://img.shields.io/badge/Node--RED-8F0000?style=flat-square&logo=nodered&logoColor=white" alt="Node-RED">
    <img src="https://img.shields.io/badge/Loki-F7B93E?style=flat-square&logo=loki&logoColor=white" alt="Loki">
    <img src="https://img.shields.io/badge/MQTT-660066?style=flat-square&logo=mqtt&logoColor=white" alt="MQTT">
    <img src="https://img.shields.io/badge/Ollama-000000?style=flat-square&logo=ollama&logoColor=white" alt="Ollama">
    <img src="https://img.shields.io/badge/Qdrant-DC2D5E?style=flat-square&logoColor=white" alt="Qdrant">
    <img src="https://img.shields.io/badge/GitLab-FC6D26?style=flat-square&logo=gitlab&logoColor=white" alt="GitLab">
    <img src="https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=github-actions&logoColor=white" alt="GitHub Actions">
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

## 🏗️ Tech Stack

Infrastructure-as-code for a self-hosted server running containerized services across storage, routing, analytics, home automation, AI, and CI/CD domains — all orchestrated with Docker Compose and managed behind an Nginx reverse proxy.

<table>
  <tr><th colspan="3" align="left">🔄 Reverse Proxy & Routing</th></tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/nginx/009639"></td>
    <td><a href="https://nginx.org">Nginx</a></td>
    <td>SSL termination, reverse proxy, multi-domain routing</td>
  </tr>
  <tr>
    <td><img width="24" src="https://img.shields.io/badge/Nginx_UI-009639?style=flat-square&logo=nginx&logoColor=white"></td>
    <td>Nginx-UI</td>
    <td>Web-based nginx configuration management</td>
  </tr>
  <tr><th colspan="3" align="left">💾 Storage & Databases</th></tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/postgresql/316192"></td>
    <td><a href="https://www.postgresql.org">PostgreSQL</a></td>
    <td>Primary relational database</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/redis/DC382D"></td>
    <td><a href="https://redis.io">Redis</a></td>
    <td>In-memory cache and message broker</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/rabbitmq/FF6600"></td>
    <td><a href="https://www.rabbitmq.com">RabbitMQ</a></td>
    <td>Message queue for job processing</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/minio/7D3EEF"></td>
    <td><a href="https://min.io">MinIO</a></td>
    <td>S3-compatible object storage</td>
  </tr>
  <tr><th colspan="3" align="left">📊 Monitoring & Observability</th></tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/prometheus/E6522C"></td>
    <td><a href="https://prometheus.io">Prometheus</a></td>
    <td>Metrics collection and alerting</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/grafana/F46800"></td>
    <td><a href="https://grafana.com">Grafana</a></td>
    <td>Dashboards and visualization</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/loki/F7B93E"></td>
    <td><a href="https://grafana.com/oss/loki">Loki</a></td>
    <td>Log aggregation</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/grafana/F46800"></td>
    <td>Promtail</td>
    <td>Log shipping agent</td>
  </tr>
  <tr><th colspan="3" align="left">🏠 Smart Home</th></tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/homeassistant/41BDF5"></td>
    <td><a href="https://www.home-assistant.io">Home Assistant</a></td>
    <td>Central home automation hub</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/nodered/8F0000"></td>
    <td><a href="https://nodered.org">Node-RED</a></td>
    <td>Visual IoT flow programming</td>
  </tr>
  <tr>
    <td><img width="24" src="https://img.shields.io/badge/Zigbee2MQTT-000000?style=flat-square"></td>
    <td><a href="https://www.zigbee2mqtt.io">Zigbee2MQTT</a></td>
    <td>Zigbee device management</td>
  </tr>
  <tr>
    <td><img width="24" src="https://img.shields.io/badge/Z--Wave-000000?style=flat-square"></td>
    <td>Z-Wave JS UI</td>
    <td>Z-Wave device control</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/eclipsemosquitto/660066"></td>
    <td><a href="https://mosquitto.org">Mosquitto</a></td>
    <td>MQTT message broker</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/influxdb/22ADF6"></td>
    <td><a href="https://www.influxdata.com">InfluxDB</a></td>
    <td>Time-series database for sensor data</td>
  </tr>
  <tr><th colspan="3" align="left">🤖 AI & Machine Learning</th></tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/ollama/000000"></td>
    <td><a href="https://ollama.com">Ollama</a></td>
    <td>LLM inference engine</td>
  </tr>
  <tr>
    <td><img width="24" src="https://img.shields.io/badge/Open_WebUI-000000?style=flat-square"></td>
    <td><a href="https://github.com/open-webui/open-webui">Open WebUI</a></td>
    <td>ChatGPT-style web interface for Ollama</td>
  </tr>
  <tr>
    <td><img width="24" src="https://img.shields.io/badge/Qdrant-DC2D5E?style=flat-square"></td>
    <td><a href="https://qdrant.tech">Qdrant</a></td>
    <td>Vector database for embeddings and similarity search</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/github/2088FF"></td>
    <td>GitHub MCP</td>
    <td>Model Context Protocol server for GitHub</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/grafana/F46800"></td>
    <td>Grafana MCP</td>
    <td>Model Context Protocol server for Grafana</td>
  </tr>
  <tr><th colspan="3" align="left">🔧 Development & CI/CD</th></tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/gitlab/FC6D26"></td>
    <td><a href="https://about.gitlab.com">GitLab CE</a></td>
    <td>Self-hosted Git repository manager</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/githubactions/2088FF"></td>
    <td>GitHub Actions Runners</td>
    <td>Self-hosted CI/CD runners (5×)</td>
  </tr>
  <tr>
    <td><img width="24" src="https://cdn.simpleicons.org/portainer/13BEF6"></td>
    <td><a href="https://www.portainer.io">Portainer</a></td>
    <td>Docker container management UI</td>
  </tr>
</table>

<div align="center">
  <p><em>requesting data in millions ops</em></p>
  <img alt="Pg" src="images/pg.png" width="100%"/>
  <img alt="Redis" src="images/redis.png" width="100%"/>
</div>

## ✨ Features

- **Multi-domain routing** — SSL-terminated reverse proxy serving `cmnw.me`, `cmnw.xyz`, `cmnw.ru`
- **Full observability stack** — Prometheus metrics, Grafana dashboards, Loki log aggregation
- **Smart home automation** — Home Assistant with Zigbee and Z-Wave device management
- **Self-hosted AI** — LLM inference with Ollama, vector search with Qdrant
- **CI/CD pipeline** — Self-hosted GitHub Actions runners and GitLab CE
- **Infrastructure as code** — All services defined in version-controlled Docker Compose files

## 📁 Project Structure

```
core/
├── docker-compose.storage.yml      # PostgreSQL, Redis, MinIO, RabbitMQ
├── docker-compose.routing.yml      # Nginx, Nginx-UI, metrics exporter
├── docker-compose.analytics.yml    # Prometheus, Grafana, Loki, Promtail
├── docker-compose.home.yml         # Home Assistant, Node-RED, InfluxDB
├── docker-compose.git.yml          # GitHub Actions runners (5×)
├── docker-compose.gitlab.yml       # GitLab CE
├── docker-compose.ai.yml           # Ollama, Open WebUI, Qdrant, MCP
├── docker-compose.control.yml      # Portainer
├── docker-compose.ai-local.yml     # Local AI with GPU passthrough
└── docker-compose.example.yml      # Template / documentation
```

---

**Maintained by:** [alexzedim](https://github.com/alexzedim)
