# Minecraft Bedrock over Azure + WireGuard

This bundle implements the simple, low-overhead design:

```text
Minecraft player
    |
    | UDP 19132
    v
Azure VM (public IPv4)
    |  nftables DNAT/SNAT
    v
wg0 10.77.0.1
    |
    | WireGuard UDP 51820
    v
Home/PVE LXC wg0 10.77.0.2
    |
    v
Minecraft Bedrock container (Docker host network, UDP 19132)
```

## Design goals

- No port-forwarding on the home router.
- No WireGuard interface on the PVE host.
- No Docker bridge/NAT in front of Minecraft.
- WireGuard runs natively inside the Azure VM and the Minecraft LXC.
- Azure only forwards UDP/19132 through the tunnel.
- Minecraft traffic from Azure to home is SNATed to `10.77.0.1`, so return routing stays simple.
- Because of SNAT, Minecraft does **not** see the original player IP addresses.

## Assumptions

- Azure VM: Debian/Ubuntu Linux with a public IPv4.
- Home side: Debian/Ubuntu unprivileged LXC with Docker installed.
- WireGuard subnet: `10.77.0.0/24`.
- Azure WireGuard address: `10.77.0.1`.
- Home WireGuard address: `10.77.0.2`.
- Minecraft Bedrock UDP port: `19132`.
- WireGuard UDP port: `51820`.

## 1. Generate keys

Run on Azure:

```bash
cd azure
sudo ./generate-keys.sh
cat keys/public.key
```

Run on the home LXC:

```bash
cd home
sudo ./generate-keys.sh
cat keys/public.key
```

Exchange only the **public** keys. Never send or commit `private.key`.

## 2. Configure Azure

Copy the example:

```bash
cd azure
cp wg0.conf.example wg0.conf
```

Edit `wg0.conf`:

- Replace `__AZURE_PRIVATE_KEY__` with `keys/private.key` contents.
- Replace `__HOME_PUBLIC_KEY__` with the home `keys/public.key` contents.

Then install:

```bash
sudo ./setup.sh
```

The script:

- installs WireGuard and nftables,
- enables IPv4 forwarding,
- installs `/etc/wireguard/wg0.conf`,
- detects the Azure VM's default-route interface,
- installs an nftables rule set that forwards only UDP/19132,
- enables and starts WireGuard and the nftables relay service.

### Azure NSG

Allow inbound:

- UDP 19132 from `Internet` (Minecraft)
- UDP 51820 from `Internet` (WireGuard)
- TCP 22 only from your administrative IP, if SSH is used

No other inbound rules are required for this tunnel.

## 3. Configure the home LXC

If WireGuard works natively inside the LXC, no `/dev/net/tun` passthrough is needed. If `wg-quick` fails because WireGuard support is unavailable, load the WireGuard kernel module on the PVE host:

```bash
modprobe wireguard
```

This loads the kernel module only; it does not create `wg0` on the PVE host.

On the home LXC:

```bash
cd home
cp wg0.conf.example wg0.conf
```

Edit `wg0.conf`:

- Replace `__HOME_PRIVATE_KEY__` with `keys/private.key` contents.
- Replace `__AZURE_PUBLIC_KEY__` with the Azure `keys/public.key` contents.
- Replace `__AZURE_PUBLIC_IP__` with the Azure VM public IPv4.

Then:

```bash
sudo ./setup.sh
```

## 4. Start Minecraft

Edit `.env` if desired, then:

```bash
docker compose up -d
```

`compose.yaml` uses `network_mode: host`, but this is the **LXC's** network namespace, not the PVE host network namespace.

Minecraft listens on UDP/19132 and is therefore reachable through `wg0` at `10.77.0.2:19132`.

## 5. Verify

Azure:

```bash
sudo ./check.sh
```

Home LXC:

```bash
sudo ./check.sh
```

Expected basic state:

- `wg show` displays a recent handshake.
- Azure can `ping 10.77.0.2`.
- Home can `ping 10.77.0.1`.
- Home shows Minecraft listening on UDP/19132.

Finally, connect a Bedrock client to:

```text
<AZURE_PUBLIC_IPV4>:19132
```

## Updating / removing

WireGuard configs:

```bash
sudo systemctl restart wg-quick@wg0
```

Azure relay rules:

```bash
sudo systemctl restart mc-relay-nft
```

Remove only the custom Azure nftables table:

```bash
sudo nft delete table ip mc_relay
```

This bundle intentionally does not flush the machine's entire nftables ruleset.

## Security notes

- Keep both WireGuard private keys secret and mode `0600`.
- Use Azure NSG as the outer firewall.
- Keep `online-mode=true` and an allow-list on the Bedrock server for private servers.
- The Azure relay intentionally exposes only UDP/19132 to the WireGuard peer.
- This simple design uses SNAT, so every player appears to the home side as `10.77.0.1` at the IP layer.
