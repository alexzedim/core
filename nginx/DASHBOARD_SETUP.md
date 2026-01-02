# Nginx Dashboard Setup Options

This document describes options for setting up a management dashboard for your Nginx reverse proxy.

## Option 1: Nginx Proxy Manager (Recommended)

Nginx Proxy Manager is a Docker-based solution that provides a web UI for managing Nginx configurations.

### Installation

Add to your `docker-compose.nginx.yml`:

```yaml
nginx-ui:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-ui
    restart: always
    ports:
        - '81:81'      # Admin UI
        - '80:80'      # HTTP
        - '443:443'    # HTTPS
    environment:
        - TZ=${TZ}
        - DB_MYSQL_HOST=db
        - DB_MYSQL_PORT=3306
        - DB_MYSQL_USER=npm
        - DB_MYSQL_PASSWORD=${NPM_DB_PASSWORD}
        - DB_MYSQL_NAME=npm
    volumes:
        - nginx-ui-data:/data
        - nginx-ui-letsencrypt:/etc/letsencrypt
    networks:
        - traefik
    depends_on:
        - db

db:
    image: 'jc21/mariadb-aria:latest'
    container_name: nginx-ui-db
    restart: always
    environment:
        - MYSQL_ROOT_PASSWORD=${NPM_DB_ROOT_PASSWORD}
        - MYSQL_DATABASE=npm
        - MYSQL_USER=npm
        - MYSQL_PASSWORD=${NPM_DB_PASSWORD}
    volumes:
        - nginx-ui-db:/var/lib/mysql
    networks:
        - traefik

volumes:
    nginx-ui-data:
    nginx-ui-letsencrypt:
    nginx-ui-db:
```

### Access

- **Admin UI**: `http://your-server:81`
- **Default Credentials**: 
  - Email: `admin@example.com`
  - Password: `changeme`

### Features

- Web-based proxy management
- SSL certificate management
- Access lists and authentication
- Backup and restore
- Real-time logs

---

## Option 2: Nginx UI (Lightweight)

A lightweight web UI for Nginx configuration management.

### Installation

```bash
docker run -d \
  --name nginx-ui \
  -p 8090:8080 \
  -v /etc/nginx:/etc/nginx \
  -v /var/log/nginx:/var/log/nginx \
  uozi/nginx-ui:latest
```

### Access

- **UI**: `https://traefik.cmnw.ru` (with basic auth)

---

## Option 3: Custom Dashboard (Current Setup)

The current setup uses a simple placeholder at `traefik.cmnw.ru` that can be replaced with:

### Static HTML Dashboard

Create `nginx/html/dashboard.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Nginx Reverse Proxy Dashboard</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .status { 
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        .service {
            border: 1px solid #ddd;
            padding: 15px;
            border-radius: 4px;
            background: #fafafa;
        }
        .service h3 { margin-top: 0; }
        .service a {
            color: #0066cc;
            text-decoration: none;
        }
        .service a:hover { text-decoration: underline; }
        .status-ok { color: #28a745; }
        .status-error { color: #dc3545; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Nginx Reverse Proxy Dashboard</h1>
        <p>Reverse proxy status and service links</p>
        
        <h2>CMNW.ME Services</h2>
        <div class="status">
            <div class="service">
                <h3>Frontend</h3>
                <p><a href="https://cmnw.me" target="_blank">cmnw.me</a></p>
                <p>Next.js Frontend Application</p>
            </div>
            <div class="service">
                <h3>API</h3>
                <p><a href="https://api.cmnw.me" target="_blank">api.cmnw.me</a></p>
                <p>Backend API Server</p>
            </div>
            <div class="service">
                <h3>Grafana</h3>
                <p><a href="https://grafana.cmnw.me" target="_blank">grafana.cmnw.me</a></p>
                <p>Monitoring & Visualization</p>
            </div>
            <div class="service">
                <h3>Prometheus</h3>
                <p><a href="https://prometheus.cmnw.me" target="_blank">prometheus.cmnw.me</a></p>
                <p>Metrics & Monitoring (Auth Required)</p>
            </div>
        </div>

        <h2>CMNW.RU Services</h2>
        <div class="status">
            <div class="service">
                <h3>Grafana</h3>
                <p><a href="https://grafana.cmnw.ru" target="_blank">grafana.cmnw.ru</a></p>
                <p>Monitoring & Visualization</p>
            </div>
            <div class="service">
                <h3>Portainer</h3>
                <p><a href="https://control.cmnw.ru" target="_blank">control.cmnw.ru</a></p>
                <p>Container Management</p>
            </div>
            <div class="service">
                <h3>MinIO API</h3>
                <p><a href="https://s3.cmnw.ru" target="_blank">s3.cmnw.ru</a></p>
                <p>S3-Compatible Object Storage</p>
            </div>
            <div class="service">
                <h3>MinIO Console</h3>
                <p><a href="https://console-s3.cmnw.ru" target="_blank">console-s3.cmnw.ru</a></p>
                <p>MinIO Management Console</p>
            </div>
            <div class="service">
                <h3>Prometheus</h3>
                <p><a href="https://prometheus.cmnw.ru" target="_blank">prometheus.cmnw.ru</a></p>
                <p>Metrics & Monitoring (Auth Required)</p>
            </div>
        </div>

        <h2>CMNW.XYZ Services</h2>
        <div class="status">
            <div class="service">
                <h3>Frontend</h3>
                <p><a href="https://cmnw.xyz" target="_blank">cmnw.xyz</a></p>
                <p>Next.js Frontend Application</p>
            </div>
        </div>

        <hr>
        <p style="color: #666; font-size: 12px;">
            Nginx Reverse Proxy | Last Updated: <span id="time"></span>
        </p>
    </div>
    <script>
        document.getElementById('time').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
```

### Update nginx configuration

Modify `nginx/conf.d/default.conf` for the dashboard:

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name traefik.cmnw.ru;

    ssl_certificate /etc/nginx/certs/cmnw.ru.pem;
    ssl_certificate_key /etc/nginx/certs/cmnw.ru.key;

    # ... SSL configuration ...

    auth_basic "Nginx Dashboard";
    auth_basic_user_file /etc/nginx/.htpasswd;

    root /usr/share/nginx/html;
    index dashboard.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

---

## Option 4: Prometheus + Grafana Monitoring

Monitor Nginx itself using Prometheus and Grafana.

### Add Nginx Exporter

```yaml
nginx-exporter:
    image: nginx/nginx-prometheus-exporter:latest
    container_name: nginx-exporter
    restart: always
    command:
        - -nginx.scrape-uri=http://nginx:80/nginx_status
    ports:
        - '9113:9113'
    networks:
        - traefik
    depends_on:
        - nginx
```

### Enable Nginx Status Module

Add to `nginx/conf.d/default.conf`:

```nginx
server {
    listen 80;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 172.16.0.0/12;  # Docker network
        deny all;
    }
}
```

### Prometheus Configuration

Add to `prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
```

---

## Recommended Setup

For your infrastructure, I recommend:

1. **Primary**: Use **Nginx Proxy Manager** for full web-based management
2. **Secondary**: Keep the **static HTML dashboard** as a lightweight fallback
3. **Monitoring**: Use **Prometheus + Grafana** to monitor Nginx performance

This provides:
- Easy configuration management
- Visual monitoring
- Backup capabilities
- Professional interface

---

## Comparison

| Feature | Nginx Proxy Manager | Nginx UI | Custom Dashboard | Prometheus |
|---------|-------------------|----------|------------------|-----------|
| Web UI | ✅ Full-featured | ✅ Lightweight | ✅ Basic | ✅ Metrics |
| Config Management | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| SSL Management | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| Monitoring | ✅ Basic | ❌ No | ❌ No | ✅ Advanced |
| Ease of Setup | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Resource Usage | Medium | Low | Very Low | Medium |
