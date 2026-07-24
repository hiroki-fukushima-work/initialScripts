#!/usr/bin/env bash
# =====================================================================
#  setupProject.sh
#  - プロジェクト固有の開発ツールをインストールするスクリプト
#  - 各ブロックを有効/無効にするには、ブロック先頭の INSTALL_xxx フラグを
#    true / false に切り替えてください
#
#  使用例 (pdfpoc プロジェクト):
#    sudo ./setupProject.sh
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------
# ▼▼▼ インストールするブロックを true / false で選択 ▼▼▼
# ---------------------------------------------------------------

INSTALL_JAVA=true         # Java (Eclipse Temurin JDK + Maven)
INSTALL_FRONTEND=true     # Frontend (Node.js LTS)
INSTALL_OCR=true          # OCR (Tesseract)
INSTALL_HEIC=true         # HEIC変換 (libheif-tools)
INSTALL_PDF=true          # PDF関連 (poppler-utils + LibreOffice)
INSTALL_UTILITY=true      # Utility (jq / curl / tree)

# Java バージョン設定 (Temurin)
JAVA_VERSION=21

# Node.js バージョン設定 (LTS メジャーバージョン)
NODE_MAJOR=20

# ---------------------------------------------------------------
# ヘルパー関数
# ---------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
ok()      { echo "[OK]    $*"; }
skip()    { echo "[SKIP]  $*"; }
section() { echo ""; echo "========================================"; echo "  $*"; echo "========================================"; }

# root または sudo 権限チェック
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] このスクリプトは root または sudo で実行してください。" >&2
  exit 1
fi

# ---------------------------------------------------------------
# パッケージリスト更新
# ---------------------------------------------------------------
info "パッケージリストを更新しています..."
apt-get update -y -qq
ok "パッケージリスト更新完了"

# ---------------------------------------------------------------
# [Java] Eclipse Temurin JDK + Maven
# ---------------------------------------------------------------
if [[ "$INSTALL_JAVA" == "true" ]]; then
  section "Java (Eclipse Temurin ${JAVA_VERSION} + Maven)"

  info "Adoptium リポジトリの GPG キーを追加しています..."
  apt-get install -y -qq wget apt-transport-https gnupg
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg

  info "Adoptium APT リポジトリを追加しています..."
  echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] \
https://packages.adoptium.net/artifactory/deb \
$(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/adoptium.list > /dev/null

  apt-get update -y -qq
  info "Temurin ${JAVA_VERSION} をインストールしています..."
  apt-get install -y -qq "temurin-${JAVA_VERSION}-jdk"

  info "Maven をインストールしています..."
  apt-get install -y -qq maven

  ok "Java セットアップ完了"
  java -version
  mvn -version
else
  skip "Java (INSTALL_JAVA=false)"
fi

# ---------------------------------------------------------------
# [Frontend] Node.js (NodeSource LTS)
# ---------------------------------------------------------------
if [[ "$INSTALL_FRONTEND" == "true" ]]; then
  section "Frontend (Node.js ${NODE_MAJOR}.x LTS)"

  info "NodeSource セットアップスクリプトを実行しています..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -

  info "Node.js をインストールしています..."
  apt-get install -y -qq nodejs

  ok "Node.js セットアップ完了"
  node -v
  npm -v
else
  skip "Frontend (INSTALL_FRONTEND=false)"
fi

# ---------------------------------------------------------------
# [OCR] Tesseract (日本語データ含む)
# ---------------------------------------------------------------
if [[ "$INSTALL_OCR" == "true" ]]; then
  section "OCR (Tesseract)"

  info "Tesseract をインストールしています..."
  apt-get install -y -qq \
    tesseract-ocr \
    tesseract-ocr-jpn \
    tesseract-ocr-eng

  ok "Tesseract セットアップ完了"
  tesseract --version
else
  skip "OCR (INSTALL_OCR=false)"
fi

# ---------------------------------------------------------------
# [HEIC変換] libheif-tools
# ---------------------------------------------------------------
if [[ "$INSTALL_HEIC" == "true" ]]; then
  section "HEIC変換 (libheif-tools)"

  info "libheif-tools をインストールしています..."
  apt-get install -y -qq libheif-tools

  ok "libheif-tools セットアップ完了"
  heif-convert --version 2>/dev/null || true
else
  skip "HEIC変換 (INSTALL_HEIC=false)"
fi

# ---------------------------------------------------------------
# [PDF関連] poppler-utils + LibreOffice
# ---------------------------------------------------------------
if [[ "$INSTALL_PDF" == "true" ]]; then
  section "PDF関連 (poppler-utils + LibreOffice)"

  info "poppler-utils をインストールしています..."
  apt-get install -y -qq poppler-utils

  info "LibreOffice をインストールしています (時間がかかる場合があります)..."
  apt-get install -y -qq \
    libreoffice-common \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress

  ok "PDF関連セットアップ完了"
  pdfinfo -v 2>&1 | head -1 || true
  soffice --version
else
  skip "PDF関連 (INSTALL_PDF=false)"
fi

# ---------------------------------------------------------------
# [Utility] jq / curl / tree
# ---------------------------------------------------------------
if [[ "$INSTALL_UTILITY" == "true" ]]; then
  section "Utility (jq / curl / tree)"

  info "ユーティリティツールをインストールしています..."
  apt-get install -y -qq \
    jq \
    curl \
    tree

  ok "Utility セットアップ完了"
  jq --version
  curl --version | head -1
  tree --version
else
  skip "Utility (INSTALL_UTILITY=false)"
fi

# ---------------------------------------------------------------
# 完了メッセージ
# ---------------------------------------------------------------
echo ""
echo "========================================================"
echo "プロジェクトセットアップが完了しました。"
echo ""
echo "インストール状況:"
echo "  Java (Temurin + Maven) : $INSTALL_JAVA"
echo "  Frontend (Node.js)     : $INSTALL_FRONTEND"
echo "  OCR (Tesseract)        : $INSTALL_OCR"
echo "  HEIC変換 (libheif)     : $INSTALL_HEIC"
echo "  PDF関連 (poppler+LO)   : $INSTALL_PDF"
echo "  Utility (jq/curl/tree) : $INSTALL_UTILITY"
echo "========================================================"
