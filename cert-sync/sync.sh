#!/bin/bash
# cert-sync — pull the cmnw.ru certificate from Selectel Certificate Manager
# and upsert it into caddy-proxy-manager via its REST API.
#
# Selectel renews the cert itself (Let's Encrypt DNS-01, the zone lives on
# Selectel DNS); this script only delivers the current material to the panel,
# which in turn pushes it to Caddy. Runs once at container start, then on a
# cron schedule (busybox crond).
#
# Selectel auth: the Certificate Manager API does NOT accept static API keys —
# it requires a Keystone (Identity v3) project token. We authenticate as a
# service user (role `member` on the project, see AGENTS.md) on every run and
# use the 24h X-Subject-Token as X-Auth-Token.
#
# Env:
#   SELECTEL_USER       service user name        (e.g. cert-sync)
#   SELECTEL_PASSWORD   service user password
#   SELECTEL_DOMAIN     Selectel account id      (e.g. 454323)
#   SELECTEL_PROJECT    project name             (e.g. cmnw)
#   SELECTEL_CERT_ID    certificate id (knox id shown in the panel's UID field)
#   CPM_BASE_URL        panel base url        (default http://cmnw-caddy-manager:3000)
#   CPM_API_TOKEN       panel API token       (Authorization: Bearer)
#   CPM_CERT_NAME       panel certificate name (default cmnw.ru)
#   CRON_SCHEDULE       cron expression        (default "0 6 * * *")
#   CPM_CERT_FIELD / CPM_KEY_FIELD  JSON field names in the panel API
#                                   (defaults certificate / privateKey)
#   DEBUG=1             dump raw API bodies on decode failures

set -euo pipefail

SELECTEL_USER="${SELECTEL_USER:?SELECTEL_USER not set}"
SELECTEL_PASSWORD="${SELECTEL_PASSWORD:?SELECTEL_PASSWORD not set}"
SELECTEL_DOMAIN="${SELECTEL_DOMAIN:?SELECTEL_DOMAIN not set}"
SELECTEL_PROJECT="${SELECTEL_PROJECT:?SELECTEL_PROJECT not set}"
SELECTEL_CERT_ID="${SELECTEL_CERT_ID:?SELECTEL_CERT_ID not set}"
CPM_BASE_URL="${CPM_BASE_URL:-http://cmnw-caddy-manager:3000}"
CPM_API_TOKEN="${CPM_API_TOKEN:?CPM_API_TOKEN not set}"
CPM_CERT_NAME="${CPM_CERT_NAME:-cmnw.ru}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 6 * * *}"
CPM_CERT_FIELD="${CPM_CERT_FIELD:-certificatePem}"
CPM_KEY_FIELD="${CPM_KEY_FIELD:-privateKeyPem}"
CPM_DOMAINS="${CPM_DOMAINS:-cmnw.ru,*.cmnw.ru}"
IDENTITY_URL="https://cloud.api.selcloud.ru/identity/v3/auth/tokens"
CERT_API="https://cloud.api.selcloud.ru/certificate-manager/v1/cert/${SELECTEL_CERT_ID}"
STATE_DIR="/var/lib/cert-sync"
FINGERPRINT_FILE="$STATE_DIR/last_fingerprint"

log()  { echo "[cert-sync $(date -Is)] $*"; }
warn() { echo "[cert-sync $(date -Is)] WARNING: $*" >&2; }
die()  { echo "[cert-sync $(date -Is)] ERROR: $*" >&2; exit 1; }

# Keystone project token via the service user. Returns the X-Subject-Token.
get_selectel_token() {
    local body resp_token
    body="$(jq -n \
        --arg user "$SELECTEL_USER" \
        --arg password "$SELECTEL_PASSWORD" \
        --arg domain "$SELECTEL_DOMAIN" \
        --arg project "$SELECTEL_PROJECT" \
        '{auth:{identity:{methods:["password"],password:{user:{name:$user,domain:{name:$domain},password:$password}}},scope:{project:{name:$project,domain:{name:$domain}}}}}')"
    resp_token="$(curl -fsS --max-time 30 -X POST \
        -H "Content-Type: application/json" \
        -d "$body" \
        -D - -o /dev/null \
        "$IDENTITY_URL" | tr -d '\r' | awk 'tolower($1)=="x-subject-token:"{print $2}')" \
        || die "Selectel identity auth failed"
    [ -n "$resp_token" ] || die "Selectel identity auth returned no X-Subject-Token"
    printf '%s' "$resp_token"
}

# The CM API returns raw PEM bodies.
fetch_selectel() {  # $1 = token, $2 = endpoint (ca_chain | private_key)
    curl -fsSL --max-time 60 \
        -H "X-Auth-Token: $1" \
        "${CERT_API}/$2" \
        || die "Selectel API call failed for $2"
}

sync_once() {
    local token cert key fingerprint panel_json cert_id
    token="$(get_selectel_token)"
    cert="$(fetch_selectel "$token" ca_chain)"
    key="$(fetch_selectel "$token" private_key)"

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
        --argjson domains "$(printf '%s' "$CPM_DOMAINS" | jq -Rc 'split(",")')" \
        '{name: $name, type: "imported", domainNames: $domains} + {($cfield): $cert} + {($kfield): $key}')"

    if [ -z "$cert_id" ]; then
        log "certificate '$CPM_CERT_NAME' not found in panel — creating"
        curl -fsS -o /dev/null --max-time 30 \
            -X POST -H "Authorization: Bearer ${CPM_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$payload" "${CPM_BASE_URL}/api/v1/certificates" \
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
