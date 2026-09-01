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
apt-get install -y wireguard wireguard-tools nftables iproute2

WAN_IF="$(ip route show default | awk '/default/ {print $5; exit}')"
if [[ -z "${WAN_IF}" ]]; then
  echo "Could not detect default-route interface." >&2
  exit 1
fi

echo "Detected WAN interface: ${WAN_IF}"

install -d -m 700 /etc/wireguard
install -m 600 ./wg0.conf /etc/wireguard/wg0.conf

cat >/etc/sysctl.d/99-minecraft-relay.conf <<'SYSCTL'
net.ipv4.ip_forward=1
SYSCTL
sysctl --system >/dev/null

install -d -m 755 /etc/nftables.d
sed "s/__WAN_IF__/${WAN_IF}/g" ./mc-relay.nft.template > /etc/nftables.d/mc-relay.nft
install -m 644 ./mc-relay-nft.service /etc/systemd/system/mc-relay-nft.service

systemctl daemon-reload
systemctl enable --now wg-quick@wg0
systemctl enable --now mc-relay-nft

echo
echo "Azure relay installed."
wg show
