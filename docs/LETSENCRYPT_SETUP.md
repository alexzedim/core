# Let's Encrypt SSL Certificate Setup for cmnw.ru (Docker)

This guide explains how to set up automatic Let's Encrypt SSL certificates for the cmnw.ru domain using Docker and certbot.

## Overview

This setup uses Docker containers to automatically manage Let's Encrypt certificates with automatic renewal. The certbot container runs continuously and checks for certificate renewal every 12 hours.

### Benefits of This Approach
- **Fully Automated**: No manual intervention needed
- **Docker Native**: Integrates seamlessly with your Docker stack
- **Zero Downtime**: Certificates renewed without stopping services
- **Free**: Let's Encrypt provides free certificates
- **Secure**: Industry-standard TLS certificates
- **Easy**: Simple one-time setup

## Prerequisites

### Requirements
- Docker and docker-compose installed
- Domain DNS pointing to your server (128.0.0.255)
- Port 80 accessible (for ACME challenge validation)
- Port 443 accessible (for HTTPS)

## Domains Covered

The certificate covers the following domains:
- `cmnw.ru` (root domain)
- `*.cmnw.ru` (wildcard for all subdomains)
- `grafana.cmnw.ru`
- `control.cmnw.ru`
- `s3.cmnw.ru`
- `console-s3.cmnw.ru`
- `prometheus.cmnw.ru`

## Quick Start (Docker)

### Step 1: Initialize Let's Encrypt Certificate

Run the initialization script once to request the initial certificate:

```bash
bash nginx/init-letsencrypt.sh
```

This script will:
1. Check if certificate already exists
2. Start nginx container
3. Create temporary self-signed certificate
4. Start certbot container
5. Request Let's Encrypt certificate using webroot validation
6. Reload nginx with the new certificate

### Step 2: Start All Services

After initialization, start all services normally:

```bash
docker-compose -f docker-compose.nginx.yml up -d
```

### Step 3: Verify HTTPS

```bash
curl -I https://cmnw.ru
```

You should see a valid Let's Encrypt certificate.

## How It Works

### Docker Services

The setup includes two new services in [`docker-compose.nginx.yml`](../docker-compose.routing.yml):

1. **certbot**: Automatically renews certificates
   - Runs continuously
   - Checks for renewal every 12 hours
   - Uses webroot validation (no downtime)
   - Automatically reloads nginx after renewal

2. **nginx**: Updated to serve ACME challenges
   - Added `/.well-known/acme-challenge/` location
   - Mounts letsencrypt volume for certificates
   - Depends on certbot service

### Automatic Renewal Process

The certbot container runs this command continuously:

```bash
certbot renew --webroot -w /var/www/certbot --quiet
```

This process:
1. Checks every 12 hours if renewal is needed
2. Renews certificates 30 days before expiration
3. Uses webroot validation (no service interruption)
4. Automatically reloads nginx after renewal
5. Logs all activity for monitoring

## Certificate Locations

Certificates are stored in the `letsencrypt` Docker volume:

```
letsencrypt/
├── live/
│   └── cmnw.ru/
│       ├── fullchain.pem      # Full certificate chain (used in nginx)
│       ├── privkey.pem        # Private key (used in nginx)
│       ├── cert.pem           # Certificate only
│       └── chain.pem          # Intermediate certificates
├── archive/
│   └── cmnw.ru/               # Certificate history
└── renewal/
    └── cmnw.ru.conf           # Renewal configuration
```

### nginx Configuration

The nginx configuration points to the correct paths:

```nginx
ssl_certificate /etc/letsencrypt/live/cmnw.ru/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/cmnw.ru/privkey.pem;
```

## Verification

### Check Certificate Installation

```bash
# View certificate details
docker-compose -f docker-compose.nginx.yml exec certbot \
    openssl x509 -in /etc/letsencrypt/live/cmnw.ru/fullchain.pem -text -noout

# List all certificates
docker-compose -f docker-compose.nginx.yml exec certbot certbot certificates
```

### Test HTTPS Connection

```bash
# Test main domain
curl -I https://cmnw.ru

# Test subdomains
curl -I https://grafana.cmnw.ru
curl -I https://control.cmnw.ru
curl -I https://s3.cmnw.ru
curl -I https://console-s3.cmnw.ru
curl -I https://prometheus.cmnw.ru
```

### Browser Verification

1. Open https://cmnw.ru in your browser
2. Click the lock icon
3. Verify certificate is from Let's Encrypt
4. Check expiration date

## Monitoring

### Check Certbot Logs

```bash
# View certbot container logs
docker-compose -f docker-compose.nginx.yml logs certbot

# Follow logs in real-time
docker-compose -f docker-compose.nginx.yml logs -f certbot
```

### Check Certificate Expiration

```bash
# View expiration date
docker-compose -f docker-compose.nginx.yml exec certbot \
    openssl x509 -in /etc/letsencrypt/live/cmnw.ru/fullchain.pem -noout -dates
```

### Manual Renewal Test

```bash
# Test renewal process (dry run)
docker-compose -f docker-compose.nginx.yml exec certbot \
    certbot renew --dry-run --verbose
```

## Troubleshooting

### Certificate Request Failed

**Error: "Address already in use"**
- Port 80 is in use by another service
- Solution: Stop conflicting service or use different port

**Error: "Connection refused"**
- Firewall blocking port 80
- Solution: Allow port 80 temporarily for ACME validation

**Error: "Domain validation failed"**
- DNS not pointing to server
- Solution: Verify DNS records point to 128.0.0.255

### Check Certbot Status

```bash
# Check if certbot container is running
docker-compose -f docker-compose.nginx.yml ps certbot

# Restart certbot container
docker-compose -f docker-compose.nginx.yml restart certbot
```

### Certificate Not Loading in nginx

**Check nginx configuration:**
```bash
docker-compose -f docker-compose.nginx.yml exec nginx nginx -t
```

**Check certificate permissions:**
```bash
docker-compose -f docker-compose.nginx.yml exec certbot \
    ls -la /etc/letsencrypt/live/cmnw.ru/
```

**Reload nginx:**
```bash
docker-compose -f docker-compose.nginx.yml exec nginx nginx -s reload
```

### Renewal Not Working

**Check renewal logs:**
```bash
docker-compose -f docker-compose.nginx.yml logs certbot | grep -i renew
```

**Manual renewal:**
```bash
docker-compose -f docker-compose.nginx.yml exec certbot \
    certbot renew --force-renewal --verbose
```

## Switching from Cloudflare Certificates

If migrating from Cloudflare Origin Certificates:

1. **Backup old certificates:**
   ```bash
   cp -r nginx/certs nginx/certs.backup
   ```

2. **Run initialization script:**
   ```bash
   bash nginx/init-letsencrypt.sh
   ```

3. **Verify HTTPS works:**
   ```bash
   curl -I https://cmnw.ru
   ```

4. **Remove old certificates (optional):**
   ```bash
   rm -rf nginx/certs
   ```

## Advanced Configuration

### Custom Email for Renewal Notifications

Edit [`nginx/init-letsencrypt.sh`](../nginx/init-letsencrypt.sh) and change:

```bash
EMAIL="admin@cmnw.ru"
```

### Adjust Renewal Check Interval

Edit the certbot service in [`docker-compose.nginx.yml`](../docker-compose.routing.yml):

```yaml
entrypoint: /bin/sh -c "trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet; sleep 24h & wait $${!}; done"
```

Change `sleep 12h` to your desired interval (e.g., `24h`, `6h`).

### Add More Domains

To add more domains to the certificate:

1. Edit [`nginx/init-letsencrypt.sh`](../nginx/init-letsencrypt.sh)
2. Add domains to the certbot command:
   ```bash
   -d newdomain.cmnw.ru
   ```
3. Run initialization script again:
   ```bash
   bash nginx/init-letsencrypt.sh
   ```

## Security Best Practices

1. **Keep Docker images updated:**
   ```bash
   docker-compose -f docker-compose.nginx.yml pull
   docker-compose -f docker-compose.nginx.yml up -d
   ```

2. **Monitor certificate expiration:**
   - Check logs regularly
   - Set calendar reminders
   - Monitor email notifications

3. **Secure private key:**
   - Ensure proper file permissions
   - Don't expose the key
   - Backup securely

4. **Use HTTPS everywhere:**
   - Redirect HTTP to HTTPS
   - Use HSTS headers
   - Enable certificate pinning (optional)

## Renewal Process

Let's Encrypt certificates are valid for 90 days. The renewal process:

1. **Day 60**: Renewal attempts begin
2. **Day 30**: Final renewal attempt
3. **Day 0**: Certificate expires (if renewal failed)

The certbot container automatically:
1. Checks for renewal every 12 hours
2. Validates domain ownership using webroot
3. Requests new certificate from Let's Encrypt
4. Installs new certificate
5. Reloads nginx
6. Logs renewal status

## Backup and Recovery

### Backup Certificates

```bash
# Backup letsencrypt volume
docker run --rm -v letsencrypt:/data -v $(pwd):/backup \
    alpine tar czf /backup/letsencrypt-backup.tar.gz -C /data .
```

### Restore Certificates

```bash
# Restore letsencrypt volume
docker run --rm -v letsencrypt:/data -v $(pwd):/backup \
    alpine tar xzf /backup/letsencrypt-backup.tar.gz -C /data
```

## Additional Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot Documentation](https://certbot.eff.org/docs/)
- [ACME Protocol](https://tools.ietf.org/html/rfc8555)
- [nginx SSL Configuration](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## Support

For issues or questions:
1. Check certbot logs: `docker-compose -f docker-compose.nginx.yml logs certbot`
2. Review nginx logs: `docker-compose -f docker-compose.nginx.yml logs nginx`
3. Check Let's Encrypt status: https://letsencrypt.status.io/
4. Visit Let's Encrypt community: https://community.letsencrypt.org/
