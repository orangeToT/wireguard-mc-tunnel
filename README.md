# Azure + WireGuard 経由の Minecraft Bedrock サーバー公開

この一式は、シンプルでオーバーヘッドの小さい次の構成を実現します。

```text
Minecraft プレイヤー
    |
    | UDP 19132
    v
Azure VM（パブリック IPv4）
    |  nftables DNAT/SNAT
    v
wg0 10.77.0.1
    |
    | WireGuard UDP 51820
    v
自宅/PVE LXC wg0 10.77.0.2
    |
    v
Minecraft Bedrock コンテナ（Dockerホストネットワーク、UDP 19132）
```

## 設計目標

- 自宅ルーターでポートフォワーディングを行わない。
- PVEホスト上にWireGuardインターフェースを作成しない。
- Minecraftの手前にDockerブリッジやNATを置かない。
- WireGuardをAzure VMとMinecraft用LXCの内部で直接動作させる。
- Azureからトンネルへ転送するのはUDP/19132だけにする。
- Azureから自宅へのMinecraft通信を`10.77.0.1`にSNATし、戻りの経路制御を単純にする。
- SNATを使用するため、Minecraftからプレイヤー本来のIPアドレスは**見えない**。

## 前提条件

- Azure VM：パブリックIPv4を持つDebian/Ubuntu Linux。
- 自宅側：DockerをインストールしたDebian/Ubuntuの非特権LXC。
- WireGuardサブネット：`10.77.0.0/24`。
- Azure側のWireGuardアドレス：`10.77.0.1`。
- 自宅側のWireGuardアドレス：`10.77.0.2`。
- Minecraft BedrockのUDPポート：`19132`。
- WireGuardのUDPポート：`51820`。

## 1. 鍵を生成する

Azure側で実行します。

```bash
cd azure
sudo ./generate-keys.sh
cat keys/public.key
```

自宅のLXC側で実行します。

```bash
cd home
sudo ./generate-keys.sh
cat keys/public.key
```

交換するのは**公開鍵**だけです。`private.key`は送信したりコミットしたりしないでください。

## 2. Azureを設定する

設定例をコピーします。

```bash
cd azure
cp wg0.conf.example wg0.conf
```

`wg0.conf`を編集します。

- `__AZURE_PRIVATE_KEY__`を`keys/private.key`の内容に置き換える。
- `__HOME_PUBLIC_KEY__`を自宅側の`keys/public.key`の内容に置き換える。

続いてインストールします。

```bash
sudo ./setup.sh
```

このスクリプトは次の処理を行います。

- WireGuardとnftablesをインストールする。
- IPv4フォワーディングを有効にする。
- `/etc/wireguard/wg0.conf`をインストールする。
- Azure VMのデフォルトルートに使用されているインターフェースを検出する。
- UDP/19132だけを転送するnftablesルールセットをインストールする。
- WireGuardとnftablesリレーサービスを有効化して起動する。

### Azure NSG

次の受信通信を許可します。

- `Internet`からのUDP 19132（Minecraft）
- `Internet`からのUDP 51820（WireGuard）
- SSHを使用する場合、管理元IPからのTCP 22のみ

このトンネルに必要な受信規則は以上です。

## 3. 自宅のLXCを設定する

LXC内でWireGuardが直接動作する場合、`/dev/net/tun`のパススルーは必要ありません。WireGuardを利用できず`wg-quick`が失敗する場合は、PVEホストでWireGuardカーネルモジュールを読み込みます。

```bash
modprobe wireguard
```

これはカーネルモジュールを読み込むだけであり、PVEホスト上に`wg0`を作成するものではありません。

自宅のLXC側で次を実行します。

```bash
cd home
cp wg0.conf.example wg0.conf
```

`wg0.conf`を編集します。

- `__HOME_PRIVATE_KEY__`を`keys/private.key`の内容に置き換える。
- `__AZURE_PUBLIC_KEY__`をAzure側の`keys/public.key`の内容に置き換える。
- `__AZURE_PUBLIC_IP__`をAzure VMのパブリックIPv4に置き換える。

続いて実行します。

```bash
sudo ./setup.sh
```

## 4. Minecraftを起動する

必要に応じて`.env`を編集し、次を実行します。

```bash
docker compose up -d
```

`compose.yaml`は`network_mode: host`を使用しますが、ここでのホストネットワークはPVEホストではなく、**LXCの**ネットワーク名前空間です。

MinecraftはUDP/19132で待ち受けるため、`wg0`を経由して`10.77.0.2:19132`で到達できます。

## 5. 動作を確認する

Azure側で実行します。

```bash
sudo ./check.sh
```

自宅のLXC側で実行します。

```bash
sudo ./check.sh
```

基本的に、次の状態になっていることを確認します。

- `wg show`に最近のハンドシェイクが表示される。
- Azureから`10.77.0.2`へ`ping`が通る。
- 自宅から`10.77.0.1`へ`ping`が通る。
- 自宅側でMinecraftがUDP/19132を待ち受けている。

最後に、Bedrockクライアントから次のアドレスへ接続します。

```text
<AZURE_PUBLIC_IPV4>:19132
```

## 更新と削除

WireGuard設定を反映する場合は、次を実行します。

```bash
sudo systemctl restart wg-quick@wg0
```

Azureのリレールールを反映する場合は、次を実行します。

```bash
sudo systemctl restart mc-relay-nft
```

Azureに追加したnftablesテーブルだけを削除する場合は、次を実行します。

```bash
sudo nft delete table ip mc_relay
```

この一式は、マシン上のnftablesルールセット全体を意図的にフラッシュしません。

## セキュリティ上の注意

- 両方のWireGuard秘密鍵を外部に漏らさず、権限を`0600`に保つ。
- 外側のファイアウォールとしてAzure NSGを使用する。
- 非公開のBedrockサーバーでは`online-mode=true`とallowlistを維持する。
- AzureリレーからWireGuardピアへ公開するのは、意図的にUDP/19132だけとしている。
- このシンプルな構成ではSNATを使用するため、IPレイヤー上、自宅側ではすべてのプレイヤーが`10.77.0.1`に見える。
