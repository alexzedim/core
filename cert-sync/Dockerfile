# Manager on a schedule and reloads nginx when it changes.
#
# Pinned versions for reproducibility:
#   - Alpine 3.20 (stable, supports busybox crond out of the box)
#   - docker-cli 26.1.4 (client only — talks to the host daemon via the socket)
#   - openssl 3.x (from Alpine repos)
FROM alpine:3.20

ARG DOCKER_CLI_VERSION=26.1.4
# yapf: disable
RUN apk add --no-cache \
        ca-certificates \
        curl \
        openssl \
        docker-cli=${DOCKER_CLI_VERSION}-r0 \
        tzdata \

# Sync logic + scheduler wiring
COPY sync-cmnw-ru-cert.sh /usr/local/bin/sync-cmnw-ru-cert.sh
COPY entrypoint.sh         /usr/local/bin/entrypoint.sh
COPY crontab               /etc/crontabs/root
RUN chmod +x /usr/local/bin/sync-cmnw-ru-cert.sh /usr/local/bin/entrypoint.sh \
    && chmod 600 /etc/crontabs/root

ENV TZ=Europe/Moscow \

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
