# Azure + WireGuard 経由の Minecraft Bedrock / Java サーバー公開

この一式は、シンプルでオーバーヘッドの小さい次の構成を実現します。

```text
Minecraft プレイヤー
    |
    | Bedrock: UDP 19132 / Java: TCP 25565
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
Minecraft Java コンテナ（同じLXCのホストネットワーク、TCP 25565）
```

## 設計目標

- 自宅ルーターでポートフォワーディングを行わない。
- PVEホスト上にWireGuardインターフェースを作成しない。
- Minecraftの手前にDockerブリッジやNATを置かない。
- WireGuardをAzure VMとMinecraft用LXCの内部で直接動作させる。
- Azureからトンネルへ転送するMinecraft通信はBedrockのUDP/19132とJavaのTCP/25565だけにする。
- Azureから自宅へのMinecraft通信を`10.77.0.1`にSNATし、戻りの経路制御を単純にする。
- SNATを使用するため、Minecraftからプレイヤー本来のIPアドレスは**見えない**。

## 前提条件

- Azure VM：パブリックIPv4を持つDebian/Ubuntu Linux。
- 自宅側：DockerをインストールしたDebian/Ubuntuの非特権LXC。
- WireGuardサブネット：`10.77.0.0/24`。
- Azure側のWireGuardアドレス：`10.77.0.1`。
- 自宅側のWireGuardアドレス：`10.77.0.2`。
- Minecraft BedrockのUDPポート：`19132`。
- Minecraft JavaのTCPポート：`25565`。
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
- UDP/19132とTCP/25565を転送するnftablesルールセットをインストールする。
- WireGuardとnftablesリレーサービスを有効化して起動する。

### Azure NSG

次の受信通信を許可します。

- `Internet`からのUDP 19132（Minecraft）
- `Internet`からのTCP 25565（Minecraft Java）
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

BedrockとJavaは別々のComposeプロジェクトです。どちらもLXCのホストネットワークを使用しますが、BedrockはUDP/19132、JavaはTCP/25565で待ち受けるため、片方ずつでも同時でも起動できます。ここでのホストネットワークはPVEホストではなく、**LXCの**ネットワーク名前空間です。以下の`cd home/...`はリポジトリのルートから実行します。

### Bedrock版

自宅のLXCで`home/be`へ移動し、必要に応じて`.env`を編集します。

```bash
cd home/be
cp -n .env.example .env
docker compose up -d
```

Bedrockのワールドは`home/be/data/`に保存します。`wg0`を経由して`10.77.0.2:19132`で到達できます。停止・再起動も`home/be`で`docker compose stop`・`docker compose up -d`を実行します。

### Java版

自宅のLXCで`home/java`へ移動します。Java版の利用規約を確認し、同意する場合に限り`.env`で`EULA=TRUE`にします。参加を許可するJavaプロフィール名を`WHITELIST`にカンマ区切りで設定します。Xboxのゲーマータグとは異なる場合があります。Java版は標準でオンライン認証とホワイトリストを有効にし、RCONを無効にしています。初回起動時にホワイトリストが空なら参加者は登録されません。

```bash
cd home/java
cp -n .env.example .env
# .envのEULAとWHITELISTを確認・編集してから実行する
docker compose up -d
```

Javaのワールドは`home/java/data/`に保存します。停止・再起動も`home/java`で`docker compose stop`・`docker compose up -d`を実行します。このCompose操作はBedrockコンテナを停止・再作成しません。LXCにファイアウォールがある場合は、少なくとも`wg0`からのTCP/25565を許可してください。`network_mode: host`なので、LXCのほかのインターフェースからの到達範囲もファイアウォールで確認してください。

`VERSION=LATEST`と`itzg/minecraft-server:latest`は更新時に内容が変わります。バージョンを固定して運用する場合は、両方の値を確認して指定してください。`MEMORY`の既定値は`1G`です。必要なメモリ量はワールドや参加人数に合わせて調整してください。

### 以前の`home/compose.yaml`から移行する場合

以前の構成をLXCで稼働させている場合は、**旧Composeファイルを更新で置き換える前に**`home`で`docker compose --profile java down`を実行して両コンテナを停止・削除します。`-v`は付けません。旧構成の`home/data/`と`home/java-data/`、`home/.env`は削除しないでください。

新しいファイルを取得したら、新構成を起動する前に、存在するデータを次のようにコピーします。コピー先の`be/data`・`java/data`がまだ存在しないことと、コピーに必要な空き容量を確認してください。権限のためにコピーできない場合は`sudo cp -a`を使用します。元のデータは残します。

```bash
cd home
cp -a data be/data             # 旧Bedrockのデータがある場合
cp -a java-data java/data      # 旧Javaのデータがある場合
```

`be/.env.example`と`java/.env.example`をそれぞれの`.env`へコピーし、旧`home/.env`を参照して値を移します。Javaの旧`JAVA_EULA`・`JAVA_WHITELIST`などは、新しい`EULA`・`WHITELIST`などに対応します。新しい両サービスのデータと設定を確認してから、それぞれのディレクトリで起動してください。

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
- Java版も起動する場合、自宅側でMinecraftがTCP/25565を待ち受けている。

最後に、Bedrockクライアントから次のアドレスへ接続します。

```text
<AZURE_PUBLIC_IPV4>:19132
```

Java版クライアントからは`<AZURE_PUBLIC_IPV4>:25565`へ接続します。Azure NSGとLXCのファイアウォールでTCP/25565が許可されていることを確認し、外部回線から接続を試してください。`ping`や`wg show`だけではゲームへの接続成功は確認できません。

## 更新と削除

WireGuard設定を反映する場合は、次を実行します。

```bash
sudo systemctl restart wg-quick@wg0
```

Azureのリレールールのテンプレートを変更した場合は、Azureの`azure`ディレクトリで`sudo ./setup.sh`を実行して`/etc/nftables.d/mc-relay.nft`を更新します。すでに稼働中のサービスへ反映するには、続けて次を実行します。

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
- Java版では`ONLINE_MODE=TRUE`とホワイトリストを維持する。
- AzureリレーからWireGuardピアへ公開するMinecraft通信は、意図的にUDP/19132とTCP/25565だけとしている。
- このシンプルな構成ではSNATを使用するため、IPレイヤー上、自宅側ではすべてのプレイヤーが`10.77.0.1`に見える。
