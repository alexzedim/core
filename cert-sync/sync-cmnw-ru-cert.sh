#!/bin/sh
# sync-cmnw-ru-cert.sh — pull the cmnw.ru certificate from Yandex Cloud
# Certificate Manager and deploy it to the nginx cert directory.
#
# Idempotent: downloads to temp files, validates, and only swaps + reloads
# nginx when the cert actually changed. Safe to run on a schedule (crond).
#
# Env vars:
#   YC_CERT_ID          Yandex Cloud Certificate Manager ID (e.g. fpq65q5lufk16glvp7n4)
#   YC_AUTHORIZED_KEY   Full authorized_key.json contents (inline, no host file needed).
#                       Takes priority over YC_KEY_FILE when set.
#   YC_KEY_FILE         Path to the service-account authorized_key.json on disk
#                       (default: /secrets/authorized_key.json). Used only when
#                       YC_AUTHORIZED_KEY is unset — e.g. a host bind mount.
#
# Exits 0 on success or "no change"; non-zero on failure (so crond surfaces it).
set -eu

CERT_NAME="cmnw.ru"
CERT_ID="${YC_CERT_ID:?YC_CERT_ID is required}"
DEFAULT_KEY_FILE="/secrets/authorized_key.json"

# Workdir for downloaded cert + key temp files (cleaned up on exit).
TMP_DIR="$(mktemp -d)"
PEM_NEW="$TMP_DIR/${CERT_NAME}.pem.new"
KEY_NEW="$TMP_DIR/${CERT_NAME}.key.new"

# Resolve the key file: prefer inline env var, fall back to on-disk file.
# Either way, scrub the key file on exit so it never persists longer than needed.
if [ -n "${YC_AUTHORIZED_KEY:-}" ]; then
    KEY_FILE="$(mktemp /tmp/authorized_key.XXXXXX.json)"
    chmod 600 "$KEY_FILE"
    printf '%s' "$YC_AUTHORIZED_KEY" >"$KEY_FILE"
    trap 'rm -rf "$TMP_DIR" "$KEY_FILE"' EXIT
else
    KEY_FILE="${YC_KEY_FILE:-$DEFAULT_KEY_FILE}"
    trap 'rm -rf "$TMP_DIR"' EXIT
fi

CERT_DIR="/certs/.certs"
PEM_PATH="$CERT_DIR/${CERT_NAME}.pem"
KEY_PATH="$CERT_DIR/${CERT_NAME}.key"

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
# Parse openssl's date format ("Aug 31 14:28:56 2026 GMT") into epoch seconds.
# BusyBox date (Alpine) needs an explicit strptime format via -D; GNU date would
# accept -d "<string>" directly. Handle both, and hard-fail if neither works —
# never silently fall through to 0 (which would make every cert look "expired").
NOT_AFTER_EPOCH=$(date -d "$NOT_AFTER" -D "%b %d %H:%M:%S %Y %Z" +%s 2>/dev/null \
    || date -d "$NOT_AFTER" +%s 2>/dev/null \
    || true)
[ -n "$NOT_AFTER_EPOCH" ] || die "cannot parse cert notAfter date: $NOT_AFTER"
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
