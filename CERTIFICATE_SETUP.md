# Cloudflare Origin Certificate Setup for Traefik

This guide explains how to obtain and install Cloudflare Origin Certificates for your domains configured with Full (strict) SSL/TLS mode.

## Overview

With Cloudflare's **Full (strict)** mode, your origin server (Traefik) must present valid SSL/TLS certificates. Cloudflare Origin Certificates are free, self-signed certificates issued by Cloudflare that work perfectly for this purpose.

## Obtaining Origin Certificates

### Step 1: Access Cloudflare Dashboard
1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your account and domain
3. Go to **SSL/TLS** > **Origin Server**

### Step 2: Create Origin Certificate
1. Click **Create Certificate**
2. Choose certificate type: **RSA (2048-bit)**
3. Hostname(s): Enter the domain and wildcard (e.g., `cmnw.me`, `*.cmnw.me`)
4. Validity: Choose 15 years (maximum)
5. Click **Create**

### Step 3: Copy Certificate and Key
The dashboard will display:
- **Origin Certificate** (PEM format) - Copy everything between and including `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----`
- **Private Key** (PEM format) - Copy everything between and including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`

**⚠️ Important:** Save the private key safely. You cannot retrieve it later.

### Step 4: Repeat for All Domains
Repeat steps 1-3 for each domain:
- `cmnw.me` (wildcard: `*.cmnw.me`)
- `cmnw.ru` (wildcard: `*.cmnw.ru`)
- `cmnw.xyz` (wildcard: `*.cmnw.xyz`)

## Installing Certificates in Traefik

### Certificate File Structure
Place your certificate files in the `traefik/certs/` directory:

```
traefik/certs/
├── cmnw.me.pem      # Certificate chain
├── cmnw.me.key      # Private key
├── cmnw.ru.pem
├── cmnw.ru.key
├── cmnw.xyz.pem
└── cmnw.xyz.key
```

### File Format

**Certificate file (*.pem):**
- Must include the full certificate chain
- Format: PEM (base64-encoded)
- Content: `-----BEGIN CERTIFICATE-----` ... `-----END CERTIFICATE-----`

**Private key file (*.key):**
- Must be the corresponding private key
- Format: PEM (base64-encoded)
- Content: `-----BEGIN PRIVATE KEY-----` ... `-----END PRIVATE KEY-----`

### Installation Steps

1. **Remove placeholder certificates** (if not already done):
   ```bash
   rm D:\Projects\alexzedim\core\traefik\certs\*.pem
   rm D:\Projects\alexzedim\core\traefik\certs\*.key
   ```

2. **Copy your certificate files** to `traefik/certs/`:
   - Paste certificate content into `cmnw.me.pem`, `cmnw.ru.pem`, `cmnw.xyz.pem`
   - Paste private key content into `cmnw.me.key`, `cmnw.ru.key`, `cmnw.xyz.key`

3. **Verify file permissions** (on Linux):
   ```bash
   chmod 400 traefik/certs/*.key
   chmod 444 traefik/certs/*.pem
   ```

4. **Restart Traefik**:
   ```bash
   docker-compose -f docker-compose.traefik.yml down
   docker-compose -f docker-compose.traefik.yml up -d
   ```

## Verification

### Check Certificate Installation
1. Access Traefik Dashboard: https://traefik.cmnw.ru (or your dashboard domain)
2. Verify the certificate in your browser (click the lock icon)
3. Should show Cloudflare Origin Certificate

### Test HTTPS Connection
```bash
# Test connection from your server
curl -I https://cmnw.me
curl -I https://api.cmnw.me
curl -I https://grafana.cmnw.me
```

### Monitor Traefik Logs
```bash
docker logs -f traefik
```

Look for successful certificate loading messages.

## Troubleshooting

### Certificate Not Loading
- **Check file paths**: Ensure certificates are in `/etc/traefik/certs/` inside container
- **Check file permissions**: Ensure private keys are readable by traefik process
- **Check file format**: Verify PEM format (not DER)
- **Check traefik-dynamic.yml**: Ensure certificate paths match file names

### Cloudflare Reports Invalid Certificate
- Verify certificate is for correct domain
- Ensure certificate hasn't expired
- Check that Full (strict) mode is enabled (not Full or Flexible)

### Connection Errors
- Ensure Traefik is listening on port 443
- Check firewall rules allow inbound HTTPS (443)
- Verify Cloudflare DNS points to correct IP (128.0.0.255)

## Certificate Renewal

Cloudflare Origin Certificates last 15 years. To renew:
1. Generate new certificate from Cloudflare dashboard
2. Replace old files with new certificates
3. Traefik automatically reloads config (watch: true)

## Additional Resources

- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Traefik TLS Configuration](https://doc.traefik.io/traefik/https/tls/)
- [Full (strict) SSL/TLS Mode](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)
