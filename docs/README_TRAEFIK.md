# Traefik Multi-Domain HTTPS Setup

## Quick Start

This directory contains a production-ready Traefik v3.4 reverse proxy configuration for managing HTTPS routing across three domains with Cloudflare Full (strict) SSL/TLS mode.

### 🚀 Status: Ready for Deployment (Pending Certificate Installation)

## 📚 Documentation

Start here based on your needs:

### For Setup & Deployment
1. **[CERTIFICATE_SETUP.md](CERTIFICATE_SETUP.md)** - How to obtain and install Cloudflare Origin Certificates
2. **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** - Step-by-step deployment and verification guide

### For Understanding
3. **[CLOUDFLARE_FULL_STRICT_EXPLAINED.md](CLOUDFLARE_FULL_STRICT_EXPLAINED.md)** - Why your setup requires origin certificates
4. **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Complete overview of what was implemented

## 🎯 What This Setup Does

✅ Routes multiple domains to different services
```
cmnw.me              → cmnw-next (frontend)
api.cmnw.me          → cmnw-api (backend)
grafana.cmnw.me      → Grafana (dashboards)
prometheus.cmnw.me   → Prometheus (metrics)
... and more
```

✅ Provides HTTPS for all domains
```
HTTP (port 80)   → Redirects to HTTPS (port 443)
HTTPS (port 443) → Routed through Traefik
```

✅ Manages certificates from one place
```
traefik/traefik-dynamic.yml → All routing rules
traefik/certs/              → All SSL certificates
```

## 📋 Prerequisites

- Docker & Docker Compose
- Cloudflare account with domains configured
- Cloudflare SSL/TLS mode set to "Full (strict)"
- External network created: `docker network create traefik`

## ⚡ Quick Deployment

### 1. Install Certificates (Required First!)
```bash
# Read CERTIFICATE_SETUP.md and place certificates in:
traefik/certs/cmnw.me.pem
traefik/certs/cmnw.me.key
traefik/certs/cmnw.ru.pem
traefik/certs/cmnw.ru.key
traefik/certs/cmnw.xyz.pem
traefik/certs/cmnw.xyz.key
```

### 2. Start Traefik
```bash
cd D:\Projects\alexzedim\core
docker-compose -f docker-compose.traefik.yml up -d
```

### 3. Verify It Works
```bash
docker logs -f traefik  # Should see certificate loading
docker ps              # Should show traefik running
curl -I https://cmnw.me # Should succeed
```

## 📁 File Structure

```
D:\Projects\alexzedim\core\
├── docker-compose.traefik.yml       # Traefik service definition
├── traefik/
│   ├── traefik.yml                  # Static configuration
│   ├── traefik-dynamic.yml          # Dynamic routes & services
│   ├── traefik-dynamic.yml.bak      # Backup
│   └── certs/                       # SSL certificates directory
│       ├── cmnw.me.pem              # ← Replace with your cert
│       ├── cmnw.me.key              # ← Replace with your key
│       ├── cmnw.ru.pem
│       ├── cmnw.ru.key
│       ├── cmnw.xyz.pem
│       └── cmnw.xyz.key
├── CERTIFICATE_SETUP.md             # Certificate guide
├── DEPLOYMENT_CHECKLIST.md          # Deployment guide
├── CLOUDFLARE_FULL_STRICT_EXPLAINED.md
├── IMPLEMENTATION_SUMMARY.md
└── README_TRAEFIK.md               # This file
```

## 🔧 Configuration

### Static Configuration (traefik/traefik.yml)
- Entry points (HTTP, HTTPS, Traefik API)
- Providers (Docker, File)
- Logging and metrics
- Health checks
- ⚠️ Do not modify unless you know what you're doing

### Dynamic Configuration (traefik/traefik-dynamic.yml)
- All routers (URL → Service mappings)
- All services (backends)
- Middlewares (security, auth, etc.)
- TLS certificates
- ✅ Safe to modify for adding/removing routes

### Example: Add a New Service
In `traefik/traefik-dynamic.yml`:

```yaml
http:
  routers:
    my-new-service:
      rule: "Host(`mynewservice.cmnw.me`)"
      entryPoints:
        - websecure
      service: my-new-service
      tls:
        options: cloudflare-tls
  
  services:
    my-new-service:
      loadBalancer:
        servers:
          - url: "http://my-container:3000"
        healthCheck:
          path: /health
          interval: 30s
```

## 🔐 Security Features

- ✅ HTTPS everywhere (HTTP redirects)
- ✅ Cloudflare Full (strict) mode (end-to-end encryption)
- ✅ TLS 1.2+ with strong ciphers
- ✅ Security headers (CSP, X-Frame-Options, etc.)
- ✅ Authentication on admin endpoints
- ✅ Health-based routing

## 📊 Monitoring

### Dashboard
```
https://traefik.cmnw.ru
Username: traefik
Password: (update in traefik-dynamic.yml!)
```

### Metrics
```
http://localhost:8082/metrics
Prometheus metrics on port 8082
```

### Logs
```bash
# Real-time logs
docker logs -f traefik

# Check access logs
docker exec traefik tail -f /var/log/traefik/access.log
```

## 🐛 Troubleshooting

### Services show "DOWN"
- Verify service is running: `docker ps`
- Check health check endpoint is working
- Verify service is on traefik network

### Certificate errors (Error 525)
- Verify certificate files exist and are readable
- Verify PEM format (not DER)
- Check Cloudflare Full (strict) mode is enabled
- See CLOUDFLARE_FULL_STRICT_EXPLAINED.md

### Domains not routing
- Verify router is configured in traefik-dynamic.yml
- Verify service name matches
- Check Traefik dashboard for routers
- Review Traefik logs

## 🔄 Configuration Reload

No restart needed! Traefik watches configuration files:
```bash
# Edit traefik-dynamic.yml
nano traefik/traefik-dynamic.yml

# Changes apply automatically in 10-30 seconds
# Verify with: docker logs -f traefik
```

## 🚀 Adding New Services

### Option 1: Update traefik-dynamic.yml
```bash
# Edit configuration
vim traefik/traefik-dynamic.yml

# Add router and service (see example above)
# Changes apply automatically
```

### Option 2: Add to other docker-compose files
Services on the `traefik` network are automatically routable:
```yaml
networks:
  - traefik  # Add this to any service
```

## 📦 Supported Services

Routers configured for:
- cmnw-next (frontend)
- cmnw-api (backend)
- Grafana (dashboards)
- Prometheus (metrics)
- Portainer (container management)
- MinIO (object storage)

All others can be added by modifying traefik-dynamic.yml.

## 🔑 Important Notes

⚠️ **Before Deploying:**
1. Install Cloudflare Origin Certificates
2. Create docker network: `docker network create traefik`
3. Ensure all services can reach Traefik

⚠️ **Cloudflare Settings:**
- SSL/TLS mode must be "Full (strict)"
- DNS records must be orange cloud (proxied)
- IP points to 128.0.0.255

⚠️ **Security:**
- Change dashboard credentials in traefik-dynamic.yml
- Use strong passwords for all services
- Monitor logs for suspicious activity
- Keep Docker images updated

## 📞 Support

- **Configuration issues**: Check IMPLEMENTATION_SUMMARY.md
- **Certificate issues**: Follow CERTIFICATE_SETUP.md
- **Understanding why**: Read CLOUDFLARE_FULL_STRICT_EXPLAINED.md
- **Deployment help**: Use DEPLOYMENT_CHECKLIST.md

## 📈 Next Steps

1. ✅ Read CERTIFICATE_SETUP.md
2. ✅ Install Cloudflare Origin Certificates
3. ✅ Follow DEPLOYMENT_CHECKLIST.md
4. ✅ Test all domain routing
5. ✅ Monitor logs and dashboards
6. ✅ Update team on new URLs

## 📝 Git Commits

```
6d93d4f - add comprehensive cloudflare full strict mode documentation
316891d - add implementation summary
a990fe8 - add deployment checklist for traefik https setup
4db1a85 - add cloudflare origin certificate setup guide
9e18dd1 - configure traefik for multi-domain https support
d2d315f - add cmnw-next service and traefik network support
```

---

**Version**: Traefik v3.4  
**Status**: ✅ Production Ready (Pending Certificates)  
**Last Updated**: 2026-01-01
