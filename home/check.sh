#!/usr/bin/env bash
set -u

echo '=== WireGuard ==='
wg show || true

echo
echo '=== Interfaces ==='
ip -brief address show wg0 || true

echo
echo '=== Route to Azure ==='
ip route get 10.77.0.1 || true

echo
echo '=== Ping Azure ==='
ping -c 3 -W 2 10.77.0.1 || true

echo
echo '=== Minecraft UDP/19132 listener ==='
ss -lunp | grep -E '(:19132\b|Local Address)' || true

echo
echo '=== Docker containers ==='
docker compose ps 2>/dev/null || docker ps || true
