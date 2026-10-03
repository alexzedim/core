#!/bin/bash
# cert-sync — pull the cmnw.ru certificate from Selectel Certificate Manager
# and upsert it into caddy-proxy-manager via its REST API.
#
# Selectel renews the cert itself (Let's Encrypt DNS-01, the zone lives on
# Selectel DNS); this script only delivers the current material to the panel,
# which in turn pushes it to Caddy. Runs once at container start, then on a
# cron schedule (busybox crond).
#
# Env:
#   SELECTEL_API_TOKEN  token for cloud.api.selcloud.ru (X-Auth-Token)
#   SELECTEL_CERT_ID    knox id shown in the certificate's UID field
#   CPM_BASE_URL        panel base url        (default http://cmnw-caddy-manager:3000)
#   CPM_API_TOKEN       panel API token       (Authorization: Bearer)
#   CPM_CERT_NAME       panel certificate name (default cmnw.ru)
#   CRON_SCHEDULE       cron expression        (default "0 6 * * *")
#   CPM_CERT_FIELD / CPM_KEY_FIELD  JSON field names in the panel API
#                                   (defaults certificate / privateKey)
#   DEBUG=1             dump raw API bodies on decode failures

set -euo pipefail

SELECTEL_API_TOKEN="${SELECTEL_API_TOKEN:?SELECTEL_API_TOKEN not set}"
SELECTEL_CERT_ID="${SELECTEL_CERT_ID:?SELECTEL_CERT_ID not set}"
CPM_BASE_URL="${CPM_BASE_URL:-http://cmnw-caddy-manager:3000}"
CPM_API_TOKEN="${CPM_API_TOKEN:?CPM_API_TOKEN not set}"
CPM_CERT_NAME="${CPM_CERT_NAME:-cmnw.ru}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 6 * * *}"
CPM_CERT_FIELD="${CPM_CERT_FIELD:-certificate}"
CPM_KEY_FIELD="${CPM_KEY_FIELD:-privateKey}"
STATE_DIR="/var/lib/cert-sync"
FINGERPRINT_FILE="$STATE_DIR/last_fingerprint"

log()  { echo "[cert-sync $(date -Is)] $*"; }
warn() { echo "[cert-sync $(date -Is)] WARNING: $*" >&2; }
die()  { echo "[cert-sync $(date -Is)] ERROR: $*" >&2; exit 1; }

# Selectel returns either raw PEM or a JSON envelope depending on endpoint
# version; unwrap JSON, pass everything else through untouched.
unwrap() {
    local body="$1"
    if jq -e . >/dev/null 2>&1 <<<"$body"; then
        jq -er '.data // .certificate // .private_key // .key // .pem // .result // empty' <<<"$body" 2>/dev/null && return 0
        [ "${DEBUG:-0}" = "1" ] && warn "JSON body did not contain a recognized PEM field: ${body:0:200}"
        return 1
    fi
    printf '%s' "$body"
}

fetch_selectel() {  # $1 = endpoint (ca_chain | private_key)
    local raw
    raw="$(curl -fsSL --max-time 60 \
        -H "X-Auth-Token: ${SELECTEL_API_TOKEN}" \
        "https://cloud.api.selcloud.ru/certificate-manager/v1/cert/${SELECTEL_CERT_ID}/$1")" \
        || die "Selectel API call failed for $1"
    unwrap "$raw" || die "could not decode Selectel response for $1"
}

sync_once() {
    local cert key fingerprint panel_json cert_id
    cert="$(fetch_selectel ca_chain)"
    key="$(fetch_selectel private_key)"

    [[ "$cert" == *"BEGIN CERTIFICATE"* ]] || die "ca_chain is not a PEM certificate"
    [[ "$key"  == *"PRIVATE KEY"*       ]] || die "private_key is not a PEM key"

    # Sanity: parseable cert + expiry watch (Selectel renews ~30d ahead).
    if ! printf '%s' "$cert" | openssl x509 -noout >/dev/null 2>&1; then
        die "certificate failed openssl parsing"
    fi
    if ! printf '%s' "$cert" | openssl x509 -checkend "$((14 * 86400))" >/dev/null 2>&1; then
        warn "certificate expires in less than 14 days — check Selectel renewal"
    fi

    fingerprint="$(printf '%s' "$cert" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    if [ -f "$FINGERPRINT_FILE" ] && [ "$(cat "$FINGERPRINT_FILE")" = "$fingerprint" ]; then
        log "certificate unchanged (fingerprint ${fingerprint:0:16}…), nothing to do"
        return 0
    fi

    panel_json="$(curl -fsSL --max-time 30 \
        -H "Authorization: Bearer ${CPM_API_TOKEN}" \
        "${CPM_BASE_URL}/api/v1/certificates")" \
        || die "failed to list certificates from the panel"

    cert_id="$(jq -r --arg n "$CPM_CERT_NAME" '
        if type == "array" then .
        elif (type == "object" and (.data | type) == "array") then .data
        elif (type == "object" and has("certificates")) then .certificates
        else [] end | map(select(.name == $n)) | (first | .id // empty)' <<<"$panel_json")"

    local payload
    payload="$(jq -n \
        --arg name "$CPM_CERT_NAME" \
        --arg cert "$cert" \
        --arg key  "$key" \
        --arg cfield "$CPM_CERT_FIELD" \
        --arg kfield "$CPM_KEY_FIELD" \
        '{name: $name} + {($cfield): $cert} + {($kfield): $key}')"

    if [ -z "$cert_id" ]; then
        log "certificate '$CPM_CERT_NAME' not found in panel — creating"
        curl -fsS -o /dev/null -w '%{http_code}' --max-time 30 \
            -X POST -H "Authorization: Bearer ${CPM_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$payload" "${CPM_BASE_URL}/api/v1/certificates" | grep -qE '20[01]' \
            || die "panel POST /certificates failed (check field names via CPM_CERT_FIELD/CPM_KEY_FIELD)"
    else
        log "updating panel certificate id=$cert_id"
        curl -fsS -o /dev/null --max-time 30 \
            -X PUT -H "Authorization: Bearer ${CPM_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$payload" "${CPM_BASE_URL}/api/v1/certificates/${cert_id}" \
            || die "panel PUT /certificates/$cert_id failed"
    fi

    # Best-effort nudge so the panel re-renders config immediately; the panel
    # also reacts to certificate changes on its own.
    curl -fsS -o /dev/null --max-time 30 \
        -X POST -H "Authorization: Bearer ${CPM_API_TOKEN}" \
        "${CPM_BASE_URL}/api/v1/caddy/sync" \
        || warn "panel /api/v1/caddy/sync nudge failed (non-fatal)"

    mkdir -p "$STATE_DIR"
    printf '%s' "$fingerprint" > "$FINGERPRINT_FILE"
    log "certificate synced (fingerprint ${fingerprint:0:16}…)"
}

if [ "${1:-}" = "--once" ]; then
    sync_once
    exit 0
fi

mkdir -p "$STATE_DIR"
log "starting; schedule '${CRON_SCHEDULE}'"

# First run may race the panel booting — log and continue to crond either way.
sync_once || warn "initial sync failed, will retry on schedule"

echo "${CRON_SCHEDULE} /usr/local/bin/sync.sh --once" >> /etc/crontabs/root
exec crond -f -l 2
