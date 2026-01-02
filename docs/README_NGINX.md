# Nginx Reverse Proxy Configuration

This document describes the nginx reverse proxy setup that replaces Traefik for routing traffic to your services across multiple domains.

## Overview

The nginx configuration provides:
- **HTTPS/TLS termination** with Cloudflare Origin Certificates
- **Multi-domain routing** for `cmnw.me`, `cmnw.ru`, and `cmnw.xyz`
- **Security headers** for all responses
- **Rate limiting** to prevent abuse
- **Basic authentication** for protected services (Prometheus, Dashboard)
- **HTTP/2 support** for improved performance
- **Gzip compression** for bandwidth optimization

## Architecture

```
Internet (Cloudflare)
    ↓
Nginx Reverse Proxy (Port 80/443)
    ├── cmnw.me → Frontend (8081), API (8080), Grafana (3000), Prometheus (9090)
    ├── cmnw.ru → Dashboard (UI), Grafana (3000), Portainer (9000), MinIO (9000/9001), Prometheus (9090)
    └── cmnw.xyz → Frontend (8081)
```

## File Structure

```
nginx/
├── nginx.conf              # Main nginx configuration
├── conf.d/
│   └── default.conf        # Virtual hosts and routing rules
├── .htpasswd.example       # Example basic auth file
└── .htpasswd               # Actual basic auth file (create from example)
```

## Configuration Details

### SSL/TLS Configuration

All domains use Cloudflare Origin Certificates with the following settings:

- **Protocol**: TLS 1.2 and TLS 1.3
- **Ciphers**: 
  - ECDHE-RSA-AES256-GCM-SHA384
  - ECDHE-RSA-CHACHA20-POLY1305
  - ECDHE-RSA-AES128-GCM-SHA256
  - ECDHE-RSA-AES128-CBC-SHA256
- **Session Cache**: Shared SSL cache (10m)
- **HSTS**: Enabled with 1-year max-age and preload

### Domain Routing

#### CMNW.ME
- **cmnw.me** → Frontend (Next.js) on port 8081
- **api.cmnw.me** → Backend API on port 8080
- **grafana.cmnw.me** → Grafana Dashboard on port 3000
- **prometheus.cmnw.me** → Prometheus (auth required) on port 9090

#### CMNW.RU
- **traefik.cmnw.ru** → Nginx Dashboard/UI (auth required)
- **grafana.cmnw.ru** → Grafana Dashboard on port 3000
- **control.cmnw.ru** → Portainer on port 9000
- **s3.cmnw.ru** → MinIO API on port 9000
- **console-s3.cmnw.ru** → MinIO Console on port 9001
- **prometheus.cmnw.ru** → Prometheus (auth required) on port 9090

#### CMNW.XYZ
- **cmnw.xyz** → Frontend (Next.js) on port 8081

### Security Headers

All responses include:
- `X-Frame-Options: SAMEORIGIN` - Prevent clickjacking
- `X-Content-Type-Options: nosniff` - Prevent MIME type sniffing
- `X-XSS-Protection: 1; mode=block` - Enable XSS protection
- `Referrer-Policy: strict-origin-when-cross-origin` - Control referrer information
- `Permissions-Policy: camera=(), microphone=(), geolocation=()` - Disable unnecessary permissions
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload` - Force HTTPS

### Rate Limiting

Two rate limit zones are configured:

1. **General Zone** (50 req/s average, 100 req/s burst)
   - Applied to most services
   - Burst limit: 100 requests

2. **API Zone** (100 req/s average, 200 req/s burst)
   - Applied to API endpoints
   - Burst limit: 200 requests

### Basic Authentication

Protected endpoints require basic authentication:
- `prometheus.cmnw.me`
- `prometheus.cmnw.ru`
- `traefik.cmnw.ru` (Dashboard)

## Setup Instructions

### 1. Create Basic Auth File

Generate a `.htpasswd` file for authentication:

```bash
# Install apache2-utils if not already installed
sudo apt-get install apache2-utils

# Create .htpasswd file with initial user
htpasswd -c nginx/.htpasswd traefik

# Add additional users
htpasswd nginx/.htpasswd prometheus
```

Or use an online generator: https://www.web2generators.com/apache-tools/htpasswd-generator

### 2. Verify Certificate Files

Ensure all certificate files are in place:

```bash
ls -la traefik/certs/
# Should show:
# - cmnw.me.pem and cmnw.me.key
# - cmnw.ru.pem and cmnw.ru.key
# - cmnw.xyz.pem and cmnw.xyz.key
```

### 3. Start Nginx Container

```bash
# Start the nginx reverse proxy
docker-compose -f docker-compose.nginx.yml up -d

# Verify it's running
docker-compose -f docker-compose.nginx.yml ps

# Check logs
docker-compose -f docker-compose.nginx.yml logs -f nginx
```

### 4. Test Configuration

```bash
# Test nginx configuration syntax
docker-compose -f docker-compose.nginx.yml exec nginx nginx -t

# Test HTTPS connectivity
curl -k https://cmnw.me
curl -k https://api.cmnw.me
curl -k https://grafana.cmnw.me
```

## Cloudflare Configuration

### DNS Records

Ensure your Cloudflare DNS records point to your server:

```
cmnw.me          A    your.server.ip    (Proxied)
*.cmnw.me        A    your.server.ip    (Proxied)
cmnw.ru          A    your.server.ip    (Proxied)
*.cmnw.ru        A    your.server.ip    (Proxied)
cmnw.xyz         A    your.server.ip    (Proxied)
*.cmnw.xyz       A    your.server.ip    (Proxied)
```

### SSL/TLS Settings

In Cloudflare dashboard:
1. Go to SSL/TLS → Overview
2. Set to **Full (Strict)** mode
3. This ensures Cloudflare validates your origin certificate

### Origin Certificate

Your Cloudflare Origin Certificates are valid for 15 years and stored in `traefik/certs/`:
- Issued by: Cloudflare Origin CA
- Valid from: 2026-01-01 to 2040-12-28
- Supports wildcard subdomains

## Monitoring and Logs

### Access Logs

```bash
# View access logs
docker-compose -f docker-compose.nginx.yml exec nginx tail -f /var/log/nginx/access.log

# View error logs
docker-compose -f docker-compose.nginx.yml exec nginx tail -f /var/log/nginx/error.log
```

### Health Check

The nginx container includes a health check endpoint:

```bash
curl http://localhost/health
# Returns: healthy
```

## Troubleshooting

### Certificate Issues

If you see SSL certificate errors:

1. Verify certificate files exist and are readable:
   ```bash
   ls -la traefik/certs/
   ```

2. Check certificate validity:
   ```bash
   openssl x509 -in traefik/certs/cmnw.me.pem -text -noout
   ```

3. Verify certificate matches key:
   ```bash
   openssl x509 -noout -modulus -in traefik/certs/cmnw.me.pem | openssl md5
   openssl rsa -noout -modulus -in traefik/certs/cmnw.me.key | openssl md5
   # Both should produce the same hash
   ```

### Authentication Issues

If basic auth is not working:

1. Verify `.htpasswd` file exists:
   ```bash
   docker-compose -f docker-compose.nginx.yml exec nginx ls -la /etc/nginx/.htpasswd
   ```

2. Test credentials:
   ```bash
   curl -u username:password https://prometheus.cmnw.me
   ```

### Proxy Connection Issues

If services are not accessible:

1. Check if backend services are running:
   ```bash
   docker ps | grep -E "8080|8081|3000|9000|9001|9090"
   ```

2. Verify network connectivity:
   ```bash
   docker-compose -f docker-compose.nginx.yml exec nginx ping 128.0.0.255
   ```

3. Check nginx error logs:
   ```bash
   docker-compose -f docker-compose.nginx.yml logs nginx
   ```

## Performance Optimization

### Gzip Compression

Enabled for:
- text/plain, text/css, text/xml, text/javascript
- application/json, application/javascript, application/xml+rss
- font/truetype, font/opentype, image/svg+xml

### Connection Pooling

- `keepalive_timeout: 65s`
- `tcp_nopush: on` - Optimize TCP packet transmission
- `tcp_nodelay: on` - Disable Nagle's algorithm for lower latency

### Buffer Optimization

- `client_max_body_size: 100M` - Allow large file uploads
- `proxy_buffering: off` - Stream responses directly for real-time data

## Comparison with Traefik

| Feature | Nginx | Traefik |
|---------|-------|---------|
| Configuration | File-based | File + Docker labels |
| Memory Usage | ~10-20MB | ~50-100MB |
| Startup Time | ~1s | ~3-5s |
| Dashboard | Manual setup | Built-in |
| Dynamic Reloading | Requires reload | Automatic |
| Learning Curve | Moderate | Steep |
| Customization | Very flexible | Limited |

## Migration from Traefik

To migrate from Traefik to Nginx:

1. **Stop Traefik**:
   ```bash
   docker-compose -f docker-compose.traefik.yml down
   ```

2. **Start Nginx**:
   ```bash
   docker-compose -f docker-compose.nginx.yml up -d
   ```

3. **Verify all routes work**:
   ```bash
   curl -k https://cmnw.me
   curl -k https://api.cmnw.me
   curl -k https://grafana.cmnw.me
   # ... test all other routes
   ```

4. **Update DNS/Load Balancer** if needed

5. **Monitor logs** for any issues:
   ```bash
   docker-compose -f docker-compose.nginx.yml logs -f nginx
   ```

## Additional Resources

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Nginx Security Best Practices](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [HTTP/2 Specification](https://tools.ietf.org/html/rfc7540)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review nginx error logs
3. Verify Cloudflare SSL/TLS settings
4. Ensure all backend services are running and accessible
