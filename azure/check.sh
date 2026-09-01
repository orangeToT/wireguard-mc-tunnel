#!/usr/bin/env bash
set -u

echo '=== WireGuard ==='
wg show || true

echo
echo '=== Interfaces ==='
ip -brief address show wg0 || true

echo
echo '=== Route to home ==='
ip route get 10.77.0.2 || true

echo
echo '=== nftables mc_relay ==='
nft list table ip mc_relay || true

echo
echo '=== Ping home ==='
ping -c 3 -W 2 10.77.0.2 || true
