#!/bin/bash
# portainer-cert-sync — keep Portainer's TLS certificate in sync with the live
# cmnw.ru wildcard from Selectel Certificate Manager.
#
# Deployed copy: /root/deploy/control/portainer-cert-sync.sh (keep LF endings;
# it runs with bash on the server).
#
# Portainer serves /data/certs/{cert.pem,key.pem} from its volume (the old
# nginx-era cmnw.xyz cert lived there and expired 2026-07-16). Selectel renews
# the wildcard (LE DNS-01); this script re-pulls the current material with the
# same Keystone recipe as cert-sync and, when the fingerprint changes, swaps
# the files and restarts portainer (TLS material is read once at start).
#
# Runs from /etc/cron.d/portainer-cert-watch. Credentials come from the
# routing stack env (SELECTEL_* — the cert-sync service user).

set -euo pipefail

ENV_FILE=/root/deploy/routing/stack.env
CERT_DIR=/var/lib/docker/volumes/control_portainer_data/_data/certs
CM_API="https://cloud.api.selcloud.ru/certificate-manager/v1/cert"

log() { logger -t portainer-cert "$*" 2>/dev/null || true; echo "[portainer-cert $(date -Is)] $*"; }
die() { log "ERROR: $*"; exit 1; }

# raw KEY=VALUE extraction — do NOT source the stack env, values may contain
# shell-hostile characters
get_env() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1; }

SELECTEL_USER=$(get_env SELECTEL_USER)
SELECTEL_PASSWORD=$(get_env SELECTEL_PASSWORD)
SELECTEL_DOMAIN=$(get_env SELECTEL_DOMAIN)
SELECTEL_PROJECT=$(get_env SELECTEL_PROJECT)
SELECTEL_CERT_ID=$(get_env SELECTEL_CERT_ID)
export SELECTEL_USER SELECTEL_PASSWORD SELECTEL_DOMAIN SELECTEL_PROJECT SELECTEL_CERT_ID
: "${SELECTEL_USER:?}" "${SELECTEL_PASSWORD:?}" "${SELECTEL_DOMAIN:?}" "${SELECTEL_PROJECT:?}" "${SELECTEL_CERT_ID:?}"

TMP_CERT=$(mktemp /tmp/pc.cert.XXXXXX)
TMP_KEY=$(mktemp /tmp/pc.key.XXXXXX)
TMP_BODY=$(mktemp /tmp/pc.body.XXXXXX)
trap 'rm -f "$TMP_CERT" "$TMP_KEY" "$TMP_BODY"' EXIT

BODY=$(python3 -c '
import json, os
print(json.dumps({"auth": {"identity": {"methods": ["password"], "password": {"user": {
    "name": os.environ["SELECTEL_USER"], "domain": {"name": os.environ["SELECTEL_DOMAIN"]},
    "password": os.environ["SELECTEL_PASSWORD"]}}},
    "scope": {"project": {"name": os.environ["SELECTEL_PROJECT"], "domain": {"name": os.environ["SELECTEL_DOMAIN"]}}}}}))
')
printf '%s' "$BODY" > "$TMP_BODY"

TOKEN=$(curl -fsS --max-time 30 -D - -o /dev/null -H 'Content-Type: application/json' \
    --data-binary "@$TMP_BODY" https://cloud.api.selcloud.ru/identity/v3/auth/tokens | tr -d '\r' \
    | awk 'tolower($1)=="x-subject-token:"{print $2}') || die "keystone auth failed"
[ -n "$TOKEN" ] || die "no X-Subject-Token returned"

curl -fsSL --max-time 60 -H "X-Auth-Token: $TOKEN" "$CM_API/$SELECTEL_CERT_ID/ca_chain" > "$TMP_CERT" || die "ca_chain fetch failed"
curl -fsSL --max-time 60 -H "X-Auth-Token: $TOKEN" "$CM_API/$SELECTEL_CERT_ID/private_key" > "$TMP_KEY" || die "private_key fetch failed"

NEW_FP=$(openssl x509 -in "$TMP_CERT" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2) || die "new cert unparseable"
if ! openssl x509 -in "$TMP_CERT" -checkend $((14 * 86400)) >/dev/null 2>&1; then
    log "WARNING: fetched certificate expires within 14 days"
fi

CUR_FP=""
if [ -f "$CERT_DIR/cert.pem" ]; then
    CUR_FP=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true)
fi

if [ "$NEW_FP" = "$CUR_FP" ]; then
    log "certificate unchanged (${NEW_FP:0:20}...), nothing to do"
    exit 0
fi

install -m 600 "$TMP_CERT" "$CERT_DIR/cert.pem"
install -m 600 "$TMP_KEY" "$CERT_DIR/key.pem"
log "certificate updated (${CUR_FP:-none} -> ${NEW_FP:0:20}...), restarting portainer"
docker restart portainer >/dev/null
log "portainer restarted"
