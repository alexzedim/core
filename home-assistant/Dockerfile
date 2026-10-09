FROM ghcr.io/home-assistant/home-assistant:2026.9.4

COPY nuc_official.pem /usr/local/share/ca-certificates/nuc_official.pem

RUN update-ca-certificates && \
    python3 -c "import certifi; open(certifi.where(), 'a').write(open('/usr/local/share/ca-certificates/nuc_official.pem').read())"
