#!/bin/sh
# entrypoint.sh — pre-flight checks, then an initial sync on startup,
# then hand off to crond.
#
# Running once on boot means: after `docker-compose up -d`, the cert is
# reconciled immediately (no waiting until 03:15). This is what un-breaks
# cmnw.ru right away if the on-disk cert had drifted stale.
set -eu

echo "[entrypoint] cmnw-cert-sync starting; running initial sync..."

# Pre-flight: the service-account key must be provided one way or another.
if [ -z "${YC_CERT_ID:-}" ]; then
  echo "[entrypoint] ERROR: YC_CERT_ID env var is not set" >&2
  exit 2
fi
if [ -z "${YC_AUTHORIZED_KEY:-}" ] && [ ! -f "${YC_KEY_FILE:-/secrets/authorized_key.json}" ]; then
  echo "[entrypoint] ERROR: no service-account key found." >&2
  echo "[entrypoint]        Set YC_AUTHORIZED_KEY to the authorized_key.json contents," >&2
  echo "[entrypoint]        OR mount the file at /secrets/authorized_key.json." >&2
  exit 2
fi

# Initial sync is best-effort: if it fails (e.g. network not ready yet),
# don't take the container down — crond will retry on schedule.
/usr/local/bin/sync-cmnw-ru-cert.sh && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[entrypoint] initial sync exited non-zero ($rc); crond will retry tonight"
fi

echo "[entrypoint] handing off to crond (TZ=${TZ:-unknown})"

# -f foreground, -l 8 log level (notices+) so job output reaches docker logs
exec crond -f -l 8
