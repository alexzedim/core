#!/bin/sh
# sync-cmnw-ru-cert.sh — pull the cmnw.ru certificate from Yandex Cloud
# Certificate Manager and deploy it to the nginx cert directory.
#
# Idempotent: downloads to temp files, validates, and only swaps + reloads
# nginx when the cert actually changed. Safe to run on a schedule (crond).
#
# Env vars:
#   YC_CERT_ID      Yandex Cloud Certificate Manager ID (e.g. fpq65q5lufk16glvp7n4)
#   YC_KEY_FILE     Path to the service-account authorized_key.json (default: /secrets/authorized_key.json)
#
# Exits 0 on success or "no change"; non-zero on failure (so crond surfaces it).
set -eu

CERT_NAME="cmnw.ru"
CERT_ID="${YC_CERT_ID:?YC_CERT_ID is required}"
KEY_FILE="${YC_KEY_FILE:-/secrets/authorized_key.json}"

CERT_DIR="/certs/.certs"
PEM_PATH="$CERT_DIR/${CERT_NAME}.pem"
KEY_PATH="$CERT_DIR/${CERT_NAME}.key"

TMP_DIR="$(mktemp -d)"
PEM_NEW="$TMP_DIR/${CERT_NAME}.pem.new"
KEY_NEW="$TMP_DIR/${CERT_NAME}.key.new"
trap 'rm -rf "$TMP_DIR"' EXIT

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] $*"; }

die() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Authenticate the yc CLI with the service account key.
# ---------------------------------------------------------------------------
[ -f "$KEY_FILE" ] || die "service-account key not found at $KEY_FILE"
yc config set service-account-key "$KEY_FILE" >/dev/null
yc config set format json >/dev/null

# ---------------------------------------------------------------------------
# 2. Download chain + private key to temp files.
# ---------------------------------------------------------------------------
log "downloading certificate $CERT_ID from Yandex Cloud Certificate Manager..."
if ! yc certificate-manager certificate content \
      --id "$CERT_ID" \
      --chain "$PEM_NEW" \
      --key "$KEY_NEW" >/dev/null 2>&1; then
  die "yc certificate-manager certificate content failed for $CERT_ID"
fi

[ -s "$PEM_NEW" ] || die "downloaded chain is empty"
[ -s "$KEY_NEW" ] || die "downloaded private key is empty"

# ---------------------------------------------------------------------------
# 3. Validate the new cert parses and is not already expired.
#    Never deploy a broken or expired cert.
# ---------------------------------------------------------------------------
if ! openssl x509 -in "$PEM_NEW" -noout >/dev/null 2>&1; then
  die "downloaded chain does not parse as a valid X.509 certificate"
fi
NOT_AFTER=$(openssl x509 -in "$PEM_NEW" -noout -enddate | cut -d= -f2)
NOT_AFTER_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$NOT_AFTER" +%s 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
if [ "$NOT_AFTER_EPOCH" -lt "$NOW_EPOCH" ]; then
  die "downloaded certificate is already expired (notAfter=$NOT_AFTER); refusing to deploy"
fi
log "downloaded cert valid until $NOT_AFTER"

# ---------------------------------------------------------------------------
# 4. Compare against the currently-deployed cert (sha256). Skip if identical.
# ---------------------------------------------------------------------------
PEM_CHANGED=1
KEY_CHANGED=1
if [ -f "$PEM_PATH" ] && [ -f "$KEY_PATH" ]; then
  NEW_PEM_SHA=$(sha256sum "$PEM_NEW" | cut -d' ' -f1)
  OLD_PEM_SHA=$(sha256sum "$PEM_PATH" | cut -d' ' -f1)
  NEW_KEY_SHA=$(sha256sum "$KEY_NEW" | cut -d' ' -f1)
  OLD_KEY_SHA=$(sha256sum "$KEY_PATH" | cut -d' ' -f1)
  if [ "$NEW_PEM_SHA" = "$OLD_PEM_SHA" ] && [ "$NEW_KEY_SHA" = "$OLD_KEY_SHA" ]; then
    log "certificate unchanged (sha256 matches); nothing to do"
    exit 0
  fi
  PEM_CHANGED=$([ "$NEW_PEM_SHA" = "$OLD_PEM_SHA" ] && echo 0 || echo 1)
  KEY_CHANGED=$([ "$NEW_KEY_SHA" = "$OLD_KEY_SHA" ] && echo 0 || echo 1)
fi

# ---------------------------------------------------------------------------
# 5. Atomic swap into place (0600 on the private key).
# ---------------------------------------------------------------------------
mkdir -p "$CERT_DIR"
mv -f "$PEM_NEW" "$PEM_PATH"
mv -f "$KEY_NEW" "$KEY_PATH"
chmod 644 "$PEM_PATH"
chmod 600 "$KEY_PATH"
log "deployed new cert to $PEM_PATH (pem_changed=$PEM_CHANGED key_changed=$KEY_CHANGED)"

# ---------------------------------------------------------------------------
# 6. Validate nginx config, then reload. A failed reload is a hard error.
# ---------------------------------------------------------------------------
log "validating nginx config..."
if ! docker exec cmnw-nginx nginx -t >/dev/null 2>&1; then
  die "nginx -t failed after cert swap; config is broken — investigate manually"
fi

log "reloading nginx..."
if ! docker exec cmnw-nginx nginx -s reload >/dev/null 2>&1; then
  die "nginx -s reload failed; the new cert is on disk but nginx was not reloaded"
fi

log "SUCCESS: cmnw.ru certificate updated and nginx reloaded"
