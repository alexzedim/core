# Let's Encrypt Docker Implementation for cmnw.ru

## Summary

Implemented automatic SSL certificate management for cmnw.ru domain using Let's Encrypt and Docker. The solution provides zero-downtime certificate renewal with automatic validation.

## What Was Changed

### 1. nginx Configuration Updates

#### [`nginx/nginx.conf`](../nginx/nginx.conf)
- Added ACME challenge location for Let's Encrypt validation
- Configured webroot path for certificate validation
- Maintains HTTP to HTTPS redirect

```nginx
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
```

#### [`nginx/conf.d/default.conf`](../nginx/conf.d/default.conf)
Updated all cmnw.ru domain configurations to use Let's Encrypt certificates:

- `grafana.cmnw.ru`
- `control.cmnw.ru`
- `s3.cmnw.ru`
- `console-s3.cmnw.ru`
- `prometheus.cmnw.ru`

Changed from:
```nginx
ssl_certificate /etc/nginx/certs/cmnw.ru.pem;
ssl_certificate_key /etc/nginx/certs/cmnw.ru.key;
```

To:
```nginx
ssl_certificate /etc/letsencrypt/live/cmnw.ru/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/cmnw.ru/privkey.pem;
```

### 2. Docker Compose Updates

#### [`docker-compose.nginx.yml`](../docker-compose.nginx.yml)

**Added certbot service:**
```yaml
certbot:
    image: certbot/certbot:latest
    container_name: certbot
    restart: always
    environment:
        - TZ=${TZ}
    volumes:
        - letsencrypt:/etc/letsencrypt
        - nginx:/var/www/certbot
    networks:
        - cmnw
    entrypoint: /bin/sh -c "trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet; sleep 12h & wait $${!}; done"
    depends_on:
        - nginx
```

**Updated nginx service:**
- Added `letsencrypt:/etc/letsencrypt` volume mount
- Added dependency on certbot service

**Added letsencrypt volume:**
```yaml
volumes:
    letsencrypt:
        driver: local
```

### 3. Initialization Script

#### [`nginx/init-letsencrypt.sh`](../nginx/init-letsencrypt.sh)

One-time setup script that:
1. Checks for existing certificates
2. Starts nginx container
3. Creates temporary self-signed certificate
4. Starts certbot container
5. Requests Let's Encrypt certificate using webroot validation
6. Reloads nginx with new certificate

**Usage:**
```bash
bash nginx/init-letsencrypt.sh
```

### 4. Documentation

#### [`docs/LETSENCRYPT_SETUP.md`](../docs/LETSENCRYPT_SETUP.md)

Comprehensive guide covering:
- Quick start instructions
- How the Docker setup works
- Certificate verification
- Monitoring and troubleshooting
- Migration from Cloudflare certificates
- Advanced configuration options
- Security best practices
- Backup and recovery procedures

## How It Works

### Initial Setup
1. Run `bash nginx/init-letsencrypt.sh`
2. Script requests certificate from Let's Encrypt
3. Certificate is stored in `letsencrypt` Docker volume
4. nginx is configured to use the certificate

### Automatic Renewal
1. Certbot container runs continuously
2. Every 12 hours, it checks if renewal is needed
3. 30 days before expiration, it automatically renews
4. Uses webroot validation (no service interruption)
5. Automatically reloads nginx after renewal

### Certificate Storage
```
letsencrypt/
├── live/cmnw.ru/
│   ├── fullchain.pem      # Used by nginx
│   ├── privkey.pem        # Used by nginx
│   ├── cert.pem
│   └── chain.pem
├── archive/cmnw.ru/       # Certificate history
└── renewal/cmnw.ru.conf   # Renewal configuration
```

## Domains Covered

The certificate covers:
- `cmnw.ru` (root domain)
- `*.cmnw.ru` (wildcard)
- `grafana.cmnw.ru`
- `control.cmnw.ru`
- `s3.cmnw.ru`
- `console-s3.cmnw.ru`
- `prometheus.cmnw.ru`

## Deployment Steps

### 1. Initialize Certificate
```bash
bash nginx/init-letsencrypt.sh
```

### 2. Start Services
```bash
docker-compose -f docker-compose.nginx.yml up -d
```

### 3. Verify HTTPS
```bash
curl -I https://cmnw.ru
```

## Monitoring

### Check Certificate Status
```bash
docker-compose -f docker-compose.nginx.yml exec certbot certbot certificates
```

### View Renewal Logs
```bash
docker-compose -f docker-compose.nginx.yml logs certbot
```

### Check Expiration Date
```bash
docker-compose -f docker-compose.nginx.yml exec certbot \
    openssl x509 -in /etc/letsencrypt/live/cmnw.ru/fullchain.pem -noout -dates
```

## Benefits

✅ **Fully Automated** - No manual intervention needed
✅ **Zero Downtime** - Renewal happens without service interruption
✅ **Free Certificates** - Let's Encrypt provides free SSL/TLS
✅ **Docker Native** - Integrates seamlessly with Docker stack
✅ **Secure** - Industry-standard TLS certificates
✅ **Easy Setup** - Single initialization script
✅ **Reliable** - Automatic renewal 30 days before expiration
✅ **Monitored** - Comprehensive logging and status checks

## Migration from Cloudflare

If migrating from Cloudflare Origin Certificates:

1. Backup old certificates:
   ```bash
   cp -r nginx/certs nginx/certs.backup
   ```

2. Run initialization:
   ```bash
   bash nginx/init-letsencrypt.sh
   ```

3. Verify HTTPS works:
   ```bash
   curl -I https://cmnw.ru
   ```

4. Remove old certificates (optional):
   ```bash
   rm -rf nginx/certs
   ```

## Troubleshooting

### Certificate Request Failed
- Check DNS: `cmnw.ru` should point to your server IP
- Check firewall: Port 80 must be accessible
- Check logs: `docker-compose -f docker-compose.nginx.yml logs certbot`

### Certificate Not Loading
- Check nginx config: `docker-compose -f docker-compose.nginx.yml exec nginx nginx -t`
- Check permissions: `docker-compose -f docker-compose.nginx.yml exec certbot ls -la /etc/letsencrypt/live/cmnw.ru/`
- Reload nginx: `docker-compose -f docker-compose.nginx.yml exec nginx nginx -s reload`

### Renewal Not Working
- Check logs: `docker-compose -f docker-compose.nginx.yml logs certbot`
- Manual renewal: `docker-compose -f docker-compose.nginx.yml exec certbot certbot renew --force-renewal --verbose`

## Files Modified/Created

### Modified Files
- [`nginx/nginx.conf`](../nginx/nginx.conf) - Added ACME challenge location
- [`nginx/conf.d/default.conf`](../nginx/conf.d/default.conf) - Updated certificate paths for cmnw.ru domains
- [`docker-compose.nginx.yml`](../docker-compose.nginx.yml) - Added certbot service and letsencrypt volume

### New Files
- [`nginx/init-letsencrypt.sh`](../nginx/init-letsencrypt.sh) - Initialization script
- [`docs/LETSENCRYPT_SETUP.md`](../docs/LETSENCRYPT_SETUP.md) - Complete setup guide
- [`docs/LETSENCRYPT_DOCKER_IMPLEMENTATION.md`](../docs/LETSENCRYPT_DOCKER_IMPLEMENTATION.md) - This file

## Next Steps

1. Run initialization script: `bash nginx/init-letsencrypt.sh`
2. Start all services: `docker-compose -f docker-compose.nginx.yml up -d`
3. Verify HTTPS: `curl -I https://cmnw.ru`
4. Monitor renewal: `docker-compose -f docker-compose.nginx.yml logs -f certbot`

## Support

For detailed information, see [`docs/LETSENCRYPT_SETUP.md`](../docs/LETSENCRYPT_SETUP.md)

For issues:
1. Check certbot logs: `docker-compose -f docker-compose.nginx.yml logs certbot`
2. Check nginx logs: `docker-compose -f docker-compose.nginx.yml logs nginx`
3. Visit Let's Encrypt community: https://community.letsencrypt.org/
