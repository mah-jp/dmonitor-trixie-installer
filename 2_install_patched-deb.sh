#!/bin/bash
set -eux -o pipefail

# 2_install_patched-deb.sh (Ver.20260322) for dmonitor
# URL: https://github.com/mah-jp/dmonitor-trixie-installer

# アーキテクチャ確認 (armhf限定)
if [ "$(dpkg --print-architecture)" != 'armhf' ]; then
    echo 'エラー: このスクリプトはarmhf環境でのみ実行可能です。' >&2
    exit 1
fi

# 環境変数・パス定義
ORIG_DIR="$(pwd)"
TARGET_PATCH='patched1'

# 1. カレントディレクトリ内の最新のパッチ済みdmonitorパッケージを特定
LATEST_DEB=''
LATEST_TIME=0
for f in dmonitor_*+${TARGET_PATCH}*.deb; do
    [ -f "$f" ] || continue
    mtime=$(stat -c %Y "$f")
    if [ "$mtime" -gt "$LATEST_TIME" ]; then
        LATEST_TIME="$mtime"
        LATEST_DEB="$f"
    fi
done

# パッケージ存在チェック
if [ -z "${LATEST_DEB}" ]; then
    echo 'エラー: パッチ済み dmonitor パッケージが見つかりません。' >&2
    exit 1
fi

DMONITOR_DEB="${ORIG_DIR}/${LATEST_DEB}"
echo "インストール対象の dmonitor: ${LATEST_DEB}"

# 2. 作業用の一時ディレクトリ作成と移動
WORK_DIR=$(mktemp -d)

# 終了時に一時ディレクトリを削除
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

cd "${WORK_DIR}"

# 3. パッチ済みdmonitorのインストール
sudo apt install "${DMONITOR_DEB}"

# 4. WiringPi最新バージョンのURL取得 (GitHub API)
echo 'WiringPiの最新バージョンを確認中...'
WIRINGPI_URL=$(curl -s https://api.github.com/repos/WiringPi/WiringPi/releases/latest | grep "browser_download_url.*armhf\.deb" | cut -d '"' -f 4 || true)

# URL取得チェック
if [ -z "${WIRINGPI_URL}" ]; then
    echo 'エラー: WiringPiの最新バージョンのURLを取得できませんでした。' >&2
    exit 1
fi

# 5. WiringPiのダウンロードとインストール
WIRINGPI_DEB=$(basename "${WIRINGPI_URL}")
echo "WiringPiの最新バージョン (${WIRINGPI_DEB}) を一時ディレクトリへダウンロードします。"
wget "${WIRINGPI_URL}"
sudo apt install "./${WIRINGPI_DEB}"

# 完了
echo '✅ パッチ適用済みdmonitorのインストールが完了しました。'

# IPv4アドレスのみをカンマやスペース区切りから抽出 (念のためIPv6を除外)
IP_LIST=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
if [ -n "$IP_LIST" ]; then
    echo 'OSを再起動してから、以下のURLでdmonitorの動作を確認してみてください：'
    for IP in $IP_LIST; do
        echo "  - http://${IP}/"
    done
else
    echo 'OSを再起動してから、dmonitorの動作を確認してみてください。'
fi
