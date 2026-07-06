#!/bin/sh
# entrypoint.sh — run an initial sync on startup, then hand off to crond.
#
# Running once on boot means: after `docker-compose up -d`, the cert is
# reconciled immediately (no waiting until 03:15). This is what un-breaks
# cmnw.ru right away if the on-disk cert had drifted stale.
set -eu

echo "[entrypoint] cmnw-cert-sync starting; running initial sync..."

# Initial sync is best-effort: if it fails (e.g. network not ready yet),
# don't take the container down — crond will retry on schedule.
/usr/local/bin/sync-cmnw-ru-cert.sh && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[entrypoint] initial sync exited non-zero ($rc); crond will retry tonight"
fi

echo "[entrypoint] handing off to crond (TZ=$(cat /etc/timezone 2>/dev/null || echo unknown))"

# -f foreground, -l 8 log level (notices+) so job output reaches docker logs
exec crond -f -l 8
