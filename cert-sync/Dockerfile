FROM alpine:3.22

RUN apk add --no-cache curl jq openssl bash tzdata

COPY sync.sh /usr/local/bin/sync.sh
RUN chmod +x /usr/local/bin/sync.sh

ENTRYPOINT ["bash", "/usr/local/bin/sync.sh"]
