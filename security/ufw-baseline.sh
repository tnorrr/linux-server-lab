#!/bin/bash
#
# ufw-baseline.sh — idempotent firewall baseline for this server.
# Safe to re-run; ufw ignores duplicate rules rather than erroring.
#
# Review the port list below before running — it matches this specific
# server's services (see HARDENING.md), not a generic template.
#
# Usage: sudo bash security/ufw-baseline.sh

set -euo pipefail

echo "Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

echo "Allowing SSH (adjust port if you didn't move it off 22)..."
ufw allow 2222/tcp

echo "Allowing base web service..."
ufw allow 80/tcp

echo "Allowing homelab service ports..."
ufw allow 8181/tcp   # Nginx Proxy Manager admin
ufw allow 8443/tcp   # Nginx Proxy Manager proxied HTTPS
ufw allow 9443/tcp   # Portainer
ufw allow 3001/tcp   # Uptime Kuma
ufw allow 8080/tcp   # Vaultwarden (internal, proxied via NPM)
ufw allow 8096/tcp   # Jellyfin
ufw allow 3000/tcp   # Homepage
ufw allow 53/tcp     # Pi-hole DNS
ufw allow 53/udp     # Pi-hole DNS
ufw allow 8090/tcp   # Pi-hole admin

echo "Enabling ufw..."
ufw --force enable

echo "Done. Current status:"
ufw status verbose
