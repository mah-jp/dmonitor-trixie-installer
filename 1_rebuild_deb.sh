#!/bin/bash
set -eux -o pipefail

# 1_rebuild_deb.sh (Ver.20260322) for dmonitor
# URL: https://github.com/mah-jp/dmonitor-trixie-installer

# アーキテクチャ確認 (armhf限定)
if [ "$(dpkg --print-architecture)" != 'armhf' ]; then
    echo 'エラー: このスクリプトはarmhf環境でのみ実行可能です。' >&2
    exit 1
fi

# 環境変数・パス定義
ORIG_DIR="$(pwd)"
KEYRINGS_DIR='/etc/apt/keyrings'
KEYRING_FILE='jarl-archive-keyring.gpg'
KEYRING_PATH="${KEYRINGS_DIR}/${KEYRING_FILE}"
DL_LIST_FILE='jarl.list'
DL_KEY_FILE='jarl-pkg.key'
EXTRACT_DIR='dmonitor_deb'
TARGET_PATCH='patched1'

# 1. 一時ディレクトリ作成
WORK_DIR=$(mktemp -d)

# 終了時に一時ディレクトリを削除
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# 一時ディレクトリへ移動
cd "${WORK_DIR}"

# 2. JARLリポジトリ情報の取得と鍵インポート
wget -O "${DL_LIST_FILE}" http://app.d-star.info/debian/bookworm/jarl.list
wget -O "${DL_KEY_FILE}" http://app.d-star.info/debian/bookworm/jarl-pkg.key

# キーリングディレクトリ作成
sudo mkdir -p "${KEYRINGS_DIR}"

# 鍵リストのバイナリ化保存
gpg --dearmor --yes < "${DL_KEY_FILE}" | sudo tee "${KEYRING_PATH}" > /dev/null

# jarl.listにsigned-byオプションを追記してシステム適用
sed "s|^deb |deb [signed-by=${KEYRING_PATH}] |" "${DL_LIST_FILE}" | sudo tee "/etc/apt/sources.list.d/${DL_LIST_FILE}" > /dev/null

# パッケージリスト更新
sudo apt update

# 3. dmonitorパッケージをダウンロード
apt download dmonitor

# ダウンロードファイルの特定とエラーチェック
DEB_FILES=(dmonitor_*.deb)
DEB_FILE="${DEB_FILES[0]}"
if [ ! -f "${DEB_FILE}" ]; then
    echo 'エラー: debファイルのダウンロードに失敗しました。'
    exit 1
fi

# 出力用ファイル名の決定 (アーキテクチャの前に +${TARGET_PATCH} を付与)
PATCHED_DEB="${DEB_FILE/_armhf.deb/+${TARGET_PATCH}_armhf.deb}"

# 4. debパッケージの解凍
dpkg-deb -R "${DEB_FILE}" "${EXTRACT_DIR}"

# 5. 依存関係とパッケージのバージョン情報を置換 (Trixie対応とバージョン改訂)
sed -i 's/libssl3 /libssl3t64 /g' "${EXTRACT_DIR}/DEBIAN/control"
sed -i 's/^Version: .*/&+'"${TARGET_PATCH}"'/' "${EXTRACT_DIR}/DEBIAN/control"

# 6. サービス実行環境のOSバージョン詐称 (Bookwormに見せかける)
SPOOF_DIR="${EXTRACT_DIR}/opt/dmonitor/os_spoof"
mkdir -p "${SPOOF_DIR}"

# 実機のos-releaseを元にBookworm版ダミーファイルを生成
sed -e 's/13/12/g' \
    -e 's/trixie/bookworm/g' \
    -e 's/Trixie/Bookworm/g' \
    -e '/DEBIAN_VERSION_FULL/d' \
    /etc/os-release > "${SPOOF_DIR}/os-release"

# 実機のdebian_versionを元にダミー生成 (無い場合は12.0)
if [ -f /etc/debian_version ]; then
    sed -e 's/13/12/g' -e 's/trixie/bookworm/g' /etc/debian_version > "${SPOOF_DIR}/debian_version"
else
    echo "12.0" > "${SPOOF_DIR}/debian_version"
fi

# 全.serviceファイルにBindReadOnlyPathsディレクティブを追記
for svc_file in "${EXTRACT_DIR}"/etc/systemd/system/*.service; do
    if [ -f "${svc_file}" ] && grep -q '^\[Service\]' "${svc_file}"; then
        sed -i '/^\[Service\]/a BindReadOnlyPaths=/opt/dmonitor/os_spoof/os-release:/etc/os-release\nBindReadOnlyPaths=/opt/dmonitor/os_spoof/debian_version:/etc/debian_version' "${svc_file}"
    fi
done

# 7. monitor (CGI) 内のdmonitor起動処理に対し、unshare名前空間詐称を適用
MONITOR_CGI="${EXTRACT_DIR}/var/www/cgi-bin/monitor"
if [ -f "${MONITOR_CGI}" ]; then
    sed -i -e 's|sudo /usr/bin/dmonitor '"'"'%s'"'"' %s %s %s %s|sudo unshare -m /bin/sh -c \\"mount --bind /opt/dmonitor/os_spoof/os-release /etc/os-release \&\& mount --bind /opt/dmonitor/os_spoof/debian_version /etc/debian_version \&\& exec /usr/bin/dmonitor '"'"'%s'"'"' %s %s %s %s\\"|' "${MONITOR_CGI}"
fi

# 8. 全CGIの「hostname -I」処理を環境変数SERVER_ADDRに一括置換 (Perlスクリプト作成)
PATCH_SCRIPT=$(mktemp --suffix=.pl)
cat << 'EOF' > "${PATCH_SCRIPT}"
use strict;
use warnings;

my $target = <<'BLOCK';
open my $rs , "hostname -I 2>&1 |";
my @ip = <$rs>;
close $rs;
my $result = join '' , @ip;
my $num = index ($result, ' ');
$result = substr($result, 0, $num);
$result =~ s/\s+//g;
$result =~ s/[[:cntrl:]]//g;
BLOCK

my $replace = <<'BLOCK';
#open my $rs , "hostname -I 2>&1 |";
#my @ip = <$rs>;
#close $rs;
#my $result = join '' , @ip;
#my $num = index ($result, ' ');
#$result = substr($result, 0, $num);
#$result =~ s/\s+//g;
#$result =~ s/[[:cntrl:]]//g;
$result = $ENV{"SERVER_ADDR"};
BLOCK

foreach my $file (glob("$ARGV[0]/var/www/cgi-bin/*")) {
    next unless -f $file;
    open(my $fh, "<", $file) or next;
    my $content = do { local $/; <$fh> };
    close($fh);
    
    if ($content =~ s/\Q$target\E/$replace/g) {
        open(my $out, ">", $file) or next;
        print $out $content;
        close($out);
        print "Patched IP logic: $file\n";
    }
}
EOF

perl "${PATCH_SCRIPT}" "${EXTRACT_DIR}"
rm -f "${PATCH_SCRIPT}"

# 9. パッケージ再構築
dpkg-deb --root-owner-group -b "${EXTRACT_DIR}" "${PATCHED_DEB}"

# 10. パッチ適用済みdebファイルを元ディレクトリへ配置
mv "${PATCHED_DEB}" "${ORIG_DIR}/"
echo "✅ パッチ適用済みdebファイルの作成が完了しました: ${ORIG_DIR}/${PATCHED_DEB}"
