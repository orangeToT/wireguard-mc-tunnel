#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y wireguard-tools

install -d -m 700 keys
umask 077
if [[ ! -f keys/private.key ]]; then
  wg genkey | tee keys/private.key | wg pubkey > keys/public.key
fi
chmod 600 keys/private.key
chmod 644 keys/public.key

echo "Public key:"
cat keys/public.key
