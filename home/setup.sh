#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [[ ! -f ./wg0.conf ]]; then
  echo "Missing ./wg0.conf. Copy wg0.conf.example and fill the placeholders first." >&2
  exit 1
fi

if grep -q '__[A-Z_]*__' ./wg0.conf; then
  echo "wg0.conf still contains placeholders." >&2
  exit 1
fi

apt-get update
apt-get install -y wireguard wireguard-tools iproute2

install -d -m 700 /etc/wireguard
install -m 600 ./wg0.conf /etc/wireguard/wg0.conf

systemctl enable --now wg-quick@wg0

echo
echo "Home WireGuard installed."
wg show
