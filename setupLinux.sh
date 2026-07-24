#!/usr/bin/env bash
# =====================================================================
#  setupLinux.sh
#  - Ubuntu コンテナ内の初期セットアップスクリプト
#  - インストール対象:
#      Git / Docker Engine / Docker Compose Plugin /
#      curl / jq / unzip / make
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------
# ヘルパー関数
# ---------------------------------------------------------------
info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# root または sudo 権限チェック
if [[ $EUID -ne 0 ]]; then
  error "このスクリプトは root または sudo で実行してください。"
fi

# ---------------------------------------------------------------
# 1. パッケージリストの更新
# ---------------------------------------------------------------
info "パッケージリストを更新しています..."
apt-get update -y -qq
ok "パッケージリスト更新完了"

# ---------------------------------------------------------------
# 2. 基本ツールのインストール (curl / jq / unzip / make / git)
# ---------------------------------------------------------------
info "基本ツール (curl / jq / unzip / make / git) をインストールしています..."
apt-get install -y -qq \
  ca-certificates \
  gnupg \
  lsb-release \
  curl \
  jq \
  unzip \
  make \
  git
ok "基本ツールのインストール完了"

# ---------------------------------------------------------------
# 3. Docker Engine + Docker Compose Plugin のインストール
#    (公式リポジトリを使用)
# ---------------------------------------------------------------
info "Docker の公式 GPG キーを追加しています..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ok "GPG キー追加完了"

info "Docker の APT リポジトリを追加しています..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
ok "リポジトリ追加完了"

info "Docker Engine / CLI / Containerd / Compose Plugin をインストールしています..."
apt-get update -y -qq
apt-get install -y -qq \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
ok "Docker インストール完了"

# ---------------------------------------------------------------
# 4. Docker サービスの起動・自動起動設定
#    (コンテナ内では systemd が使えない場合があるため条件分岐)
# ---------------------------------------------------------------
if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
  info "Docker サービスを有効化・起動しています..."
  systemctl enable docker
  systemctl start docker
  ok "Docker サービス起動完了"
else
  info "systemd が利用できない環境です。Docker デーモンは手動で起動してください。"
  info "  起動コマンド例: dockerd &"
fi

# ---------------------------------------------------------------
# 5. バージョン確認
# ---------------------------------------------------------------
echo ""
echo "========================================================"
echo "インストール済みバージョン確認"
echo "========================================================"
echo "  git     : $(git --version)"
echo "  curl    : $(curl --version | head -1)"
echo "  jq      : $(jq --version)"
echo "  unzip   : $(unzip -v | head -1)"
echo "  make    : $(make --version | head -1)"
echo "  docker  : $(docker --version)"
echo "  compose : $(docker compose version)"
echo "========================================================"
echo "セットアップが完了しました。"
echo ""
echo "※ Docker Compose は 'docker compose' コマンドで使用できます。"
echo "========================================================"
