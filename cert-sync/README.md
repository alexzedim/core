# cert-sync

Sidecar that keeps `cmnw.ru`'s TLS certificate (issued by **Yandex Cloud Certificate Manager**) deployed to nginx without manual file updates.

## What it does

Every night at **03:15 MSK** (and once on container startup), it:

1. Authenticates to Yandex Cloud with a service-account key.
2. Downloads the cert chain + private key via `yc certificate-manager certificate content`.
3. Validates the cert parses and is not expired.
4. Compares (sha256) against the currently-deployed files — **skips everything if unchanged**.
5. On change: atomically swaps them in and reloads nginx (`docker exec cmnw-nginx nginx -s reload`).

Yandex Cloud auto-renews the underlying Let's Encrypt cert ~30 days before expiry; this sidecar is what bridges that renewal onto the self-hosted nginx.

## Where files land

The container writes to `/certs/.certs/` inside itself, which is the **same `nginx-config` named volume** nginx reads — bind-mounted to `/mnt/nginx` on the host. So a write here appears at:

- `/mnt/nginx/.certs/cmnw.ru.{pem,key}` on the host
- `/etc/nginx/.certs/cmnw.ru.{pem,key}` inside the nginx container

No nginx config changes are needed — `nginx/conf.d/cmnw.conf` already points there.

## One-time host setup

These steps run **once** on the server (`core.cmnw`), from the Yandex Cloud console or `yc` CLI.

### 1. Create a service account + key

```bash
# Create the service account in the cmnw folder
yc iam service-account create --name cmnw-cert-sync --folder-id <FOLDER_ID>

# Grant the minimal role needed to read certificate contents
yc resource-manager folder add-access-binding <FOLDER_ID> \
    --subject serviceAccount:<SA_ID> \
    --role certificate-manager.certificates.downloader

# Create an authorized key and save it where the container will read it
sudo mkdir -p /mnt/cert-sync/secrets
yc iam key create --service-account-name cmnw-cert-sync \
    --output /mnt/cert-sync/secrets/authorized_key.json
sudo chmod 600 /mnt/cert-sync/secrets/authorized_key.json
```

### 2. Set the certificate ID

Put the `cmnw.ru` cert ID into `../.env`:

```ini
YC_CERT_ID=fpq65q5lufk16glvp7n4
```

(Confirm with `yc certificate-manager certificate list`.)

### 3. Deploy

```bash
docker-compose -f docker-compose.routing.yml up -d --build cert-sync
```

The entrypoint runs an initial sync immediately, so the cert is reconciled at startup — no waiting for 03:15.

## Operation

```bash
# Watch the nightly runs
docker logs -f cmnw-cert-sync

# Trigger a sync manually (e.g. right after a YC renewal)
docker exec cmnw-cert-sync /usr/local/bin/sync-cmnw-ru-cert.sh

# Confirm the live cert
echo | openssl s_client -connect cmnw.ru:443 -servername cmnw.ru \
    | openssl x509 -noout -dates
```

## Security notes

- The service account has **only** `certificate-manager.certificates.downloader` — it can read cert contents, nothing else.
- `authorized_key.json` lives on the host at `/mnt/cert-sync/secrets/`, bind-mounted `:ro` into the container. It is never committed (see `.gitignore`).
- The private key is written `chmod 600`; the chain is `644`.
- The script refuses to deploy any cert that fails to parse or is already expired.
