#!/bin/bash

################################################################################
# Let's Encrypt Initial Certificate Setup for Docker
#
# This script initializes Let's Encrypt certificates for cmnw.ru domain
# Run this once before starting the docker-compose stack
#
# Usage:
#   bash nginx/init-letsencrypt.sh
#
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="cmnw.ru"
EMAIL="admin@cmnw.ru"
CERT_DIR="./letsencrypt/live/${DOMAIN}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Let's Encrypt Docker Setup${NC}"
echo -e "${BLUE}Domain: ${DOMAIN}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker or docker-compose is not installed${NC}"
    exit 1
fi

# Check if certificate already exists
if [ -f "${CERT_DIR}/fullchain.pem" ] && [ -f "${CERT_DIR}/privkey.pem" ]; then
    echo -e "${GREEN}✓ Certificate already exists at ${CERT_DIR}${NC}"
    echo ""
    echo "Certificate details:"
    openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -dates
    echo ""
    echo "No action needed. Certificates will be auto-renewed by certbot container."
    exit 0
fi

echo -e "${YELLOW}Initializing Let's Encrypt certificate...${NC}"
echo ""

# Create necessary directories
mkdir -p letsencrypt/live/${DOMAIN}
mkdir -p letsencrypt/archive/${DOMAIN}
mkdir -p letsencrypt/renewal

echo -e "${YELLOW}Starting Docker containers...${NC}"

# Start only nginx and certbot services
docker-compose -f docker-compose.nginx.yml up -d nginx

# Wait for nginx to be ready
echo -e "${YELLOW}Waiting for nginx to be ready...${NC}"
sleep 5

# Create temporary self-signed certificate to allow nginx to start
if [ ! -f "${CERT_DIR}/fullchain.pem" ]; then
    echo -e "${YELLOW}Creating temporary self-signed certificate...${NC}"
    mkdir -p "${CERT_DIR}"
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${CERT_DIR}/privkey.pem" \
        -out "${CERT_DIR}/fullchain.pem" \
        -days 1 \
        -subj "/CN=${DOMAIN}" 2>/dev/null || true
fi

# Start certbot service
echo -e "${YELLOW}Starting certbot service...${NC}"
docker-compose -f docker-compose.nginx.yml up -d certbot

# Wait for certbot to initialize
echo -e "${YELLOW}Waiting for certbot to initialize...${NC}"
sleep 10

# Request certificate using webroot validation
echo -e "${YELLOW}Requesting Let's Encrypt certificate...${NC}"
docker-compose -f docker-compose.nginx.yml exec -T certbot certbot certonly \
    --webroot \
    -w /var/www/certbot \
    --agree-tos \
    --no-eff-email \
    --email "${EMAIL}" \
    -d "${DOMAIN}" \
    -d "*.${DOMAIN}" \
    -d "grafana.${DOMAIN}" \
    -d "control.${DOMAIN}" \
    -d "s3.${DOMAIN}" \
    -d "console-s3.${DOMAIN}" \
    -d "prometheus.${DOMAIN}" \
    --force-renewal 2>&1 || {
        echo -e "${RED}✗ Certificate request failed${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "1. Check DNS: cmnw.ru should point to your server IP"
        echo "2. Check firewall: Port 80 must be accessible"
        echo "3. Check logs: docker-compose -f docker-compose.nginx.yml logs certbot"
        exit 1
    }

# Verify certificate
if [ -f "${CERT_DIR}/fullchain.pem" ] && [ -f "${CERT_DIR}/privkey.pem" ]; then
    echo -e "${GREEN}✓ Certificate successfully created${NC}"
    echo ""
    echo "Certificate details:"
    openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -dates
    echo ""
else
    echo -e "${RED}✗ Certificate creation failed${NC}"
    exit 1
fi

# Reload nginx with new certificate
echo -e "${YELLOW}Reloading nginx...${NC}"
docker-compose -f docker-compose.nginx.yml exec -T nginx nginx -s reload

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Let's Encrypt setup completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Start all services: docker-compose -f docker-compose.nginx.yml up -d"
echo "2. Verify HTTPS: curl -I https://${DOMAIN}"
echo "3. Check certificate: openssl x509 -in ${CERT_DIR}/fullchain.pem -text -noout"
echo ""
echo "Automatic renewal:"
echo "  - Certbot container will check for renewal every 12 hours"
echo "  - Certificates are renewed 30 days before expiration"
echo "  - Nginx is automatically reloaded after renewal"
echo ""
