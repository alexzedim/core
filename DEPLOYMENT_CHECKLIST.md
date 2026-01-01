# Traefik Multi-Domain HTTPS Deployment Checklist

This checklist guides you through deploying the Traefik reverse proxy with multi-domain HTTPS support using Cloudflare Origin Certificates.

## Pre-Deployment

- [ ] Review `CERTIFICATE_SETUP.md` for certificate requirements
- [ ] Review `traefik/traefik.yml` static configuration
- [ ] Review `traefik/traefik-dynamic.yml` dynamic configuration
- [ ] Review `docker-compose.traefik.yml` for Traefik service definition

## Certificate Installation

- [ ] Generate Cloudflare Origin Certificate for `cmnw.me` (wildcard: `*.cmnw.me`)
  - [ ] Save certificate to `traefik/certs/cmnw.me.pem`
  - [ ] Save private key to `traefik/certs/cmnw.me.key`

- [ ] Generate Cloudflare Origin Certificate for `cmnw.ru` (wildcard: `*.cmnw.ru`)
  - [ ] Save certificate to `traefik/certs/cmnw.ru.pem`
  - [ ] Save private key to `traefik/certs/cmnw.ru.key`

- [ ] Generate Cloudflare Origin Certificate for `cmnw.xyz` (wildcard: `*.cmnw.xyz`)
  - [ ] Save certificate to `traefik/certs/cmnw.xyz.pem`
  - [ ] Save private key to `traefik/certs/cmnw.xyz.key`

- [ ] Verify certificate files exist and are readable:
  ```bash
  ls -la D:\Projects\alexzedim\core\traefik\certs\
  ```

## Docker Network Setup

- [ ] Create traefik external network:
  ```bash
  docker network create traefik
  ```

- [ ] Verify network created:
  ```bash
  docker network ls | grep traefik
  ```

## Traefik Deployment

- [ ] Set TZ environment variable in .env or shell:
  ```bash
  $env:TZ = "UTC"  # or your timezone
  ```

- [ ] Start Traefik services:
  ```bash
  cd D:\Projects\alexzedim\core
  docker-compose -f docker-compose.traefik.yml up -d
  ```

- [ ] Verify Traefik is running:
  ```bash
  docker ps | grep traefik
  ```

- [ ] Check Traefik logs for errors:
  ```bash
  docker logs -f traefik
  ```

- [ ] Wait for health check to pass (should see "healthy" status)

## Core Services Deployment

- [ ] Start core infrastructure services:
  ```bash
  docker-compose -f docker-compose.storage.yml up -d
  docker-compose -f docker-compose.analytics.yml up -d
  docker-compose -f docker-compose.control.yml up -d
  ```

- [ ] Verify services are running:
  ```bash
  docker ps | grep -E "grafana|prometheus|portainer|minio"
  ```

## CMNW Application Deployment

- [ ] Deploy cmnw services:
  ```bash
  cd D:\Projects\alexzedim\cmnw
  docker-compose -f docker-compose.core.yml up -d
  ```

- [ ] Verify cmnw services are running:
  ```bash
  docker ps | grep -E "cmnw-api|cmnw-next"
  ```

## Configuration Verification

- [ ] Access Traefik Dashboard:
  - URL: `https://traefik.cmnw.ru`
  - Verify certificate shows Cloudflare Origin CA
  - Check all routers are configured
  - Check all services are discovered

- [ ] Verify service connectivity:
  ```bash
  docker exec traefik wget -O - https://cmnw-next:8081 2>&1 | head -20
  docker exec traefik wget -O - https://cmnw-api:8080 2>&1 | head -20
  ```

## Network Connectivity Tests

- [ ] Test HTTPS access from external:
  ```bash
  curl -I https://cmnw.me
  curl -I https://api.cmnw.me
  curl -I https://grafana.cmnw.me
  curl -I https://prometheus.cmnw.me
  curl -I https://control.cmnw.ru
  ```

- [ ] Check Cloudflare DNS resolution:
  - Verify DNS records point to 128.0.0.255
  - Verify orange cloud icon (proxied) in Cloudflare dashboard

- [ ] Test certificate validity:
  - Check browser address bar for secure connection
  - View certificate details - should show Cloudflare Origin CA

## Domain Routing Verification

- [ ] **cmnw.me domain:**
  - [ ] `https://cmnw.me` → cmnw-next (port 8081)
  - [ ] `https://api.cmnw.me` → cmnw-api (port 8080)
  - [ ] `https://grafana.cmnw.me` → Grafana (port 3000)
  - [ ] `https://prometheus.cmnw.me` → Prometheus (port 9090)

- [ ] **cmnw.ru domain:**
  - [ ] `https://traefik.cmnw.ru` → Traefik Dashboard (port 8080)
  - [ ] `https://grafana.cmnw.ru` → Grafana (port 3000)
  - [ ] `https://control.cmnw.ru` → Portainer (port 9000)
  - [ ] `https://s3.cmnw.ru` → MinIO API (port 9000)
  - [ ] `https://console-s3.cmnw.ru` → MinIO Console (port 9001)
  - [ ] `https://prometheus.cmnw.ru` → Prometheus (port 9090)

- [ ] **cmnw.xyz domain:**
  - [ ] Configure as needed for additional services

## Health Checks

- [ ] Verify service health checks in Traefik dashboard
- [ ] All services should show "UP" status
- [ ] No "DOWN" or "IDLE" services visible

## Security Verification

- [ ] HTTP (port 80) redirects to HTTPS:
  ```bash
  curl -I http://cmnw.me  # Should redirect with 301 to https://
  ```

- [ ] Security headers are applied:
  ```bash
  curl -I https://cmnw.me | grep -E "X-Frame|X-Content-Type|Strict-Transport"
  ```

- [ ] Strong TLS version (1.2+) is enforced:
  ```bash
  openssl s_client -connect cmnw.me:443 -tls1_2
  ```

## Monitoring & Logging

- [ ] Check Traefik access logs:
  ```bash
  docker exec traefik tail -f /var/log/traefik/access.log
  ```

- [ ] Verify Prometheus is scraping Traefik metrics
- [ ] Create Grafana dashboard for Traefik metrics

## Documentation & Backup

- [ ] Backup certificate files to secure location
- [ ] Document dashboard passwords and access points
- [ ] Update team wiki/docs with new URLs
- [ ] Create runbooks for common operations:
  - How to restart Traefik
  - How to update certificates
  - How to add new services
  - How to troubleshoot HTTPS issues

## Ongoing Maintenance

- [ ] Set reminder to renew certificates (15 years from creation, but good practice to track)
- [ ] Monitor Traefik logs for errors
- [ ] Monitor Cloudflare analytics for traffic patterns
- [ ] Regularly test failover scenarios
- [ ] Schedule quarterly security reviews

## Troubleshooting Checklist

If issues arise, verify:

- [ ] Certificates are valid PEM format
- [ ] Certificate files are readable by Docker container
- [ ] `traefik-dynamic.yml` syntax is valid YAML
- [ ] All service hostnames in routers match actual container names
- [ ] Traefik and services are on same docker network
- [ ] Cloudflare DNS points to correct IP (128.0.0.255)
- [ ] Cloudflare SSL/TLS mode is set to "Full (strict)"
- [ ] Firewall allows ports 80 and 443 inbound
- [ ] Service health check endpoints are accessible

## Rollback Plan

If critical issues occur:

1. Stop Traefik:
   ```bash
   docker-compose -f docker-compose.traefik.yml down
   ```

2. Restore from backup configuration:
   ```bash
   git checkout traefik/
   ```

3. Address issues and redeploy

## Sign-Off

- [ ] All tests passed
- [ ] Team notified of new URLs
- [ ] Monitoring configured
- [ ] Documentation updated
- [ ] Deployment complete!

---

**Deployment Date:** _______________

**Deployed By:** _______________

**Notes:** 
