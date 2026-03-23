# dmonitor-trixie-installer: dmonitorをRaspberry Pi OS (Debian 13 Trixie) に簡単インストール

これは、JARL D-STAR委員会が提供している「dmonitor」 (アマチュア無線でのD-STARのリピータ監視ソフト) を、Raspberry Pi OS (32bit) の、2026年3月時点の最新バージョンであるDebian 13 (Trixie) 環境にインストールするための、非公式パッチ＆インストールスクリプトです。

`dmonitor V02.00`はDebian 12 (Bookworm) 環境向けにビルド・最適化されているため、そのまま最新のDebian 13 (Trixie) 環境にインストールしようとすると「依存パッケージの不整合」や「起動時のOSバージョンチェック」に引っ掛かり正常動作しません。当スクリプトは、正規の`.deb`ファイルを自動でダウンロードし、内容にパッチを当てた「改定版パッケージ」を再構築したうえで、安全にシステムへインストールします。

## 💻 必須環境・前提条件

- **dmonitor**: V02.00
- **OS**: Raspberry Pi OS 32bit (Debian 13 Trixie)
- **ネットワーク**: インターネットに接続できること

### 動作確認済の組み合わせ

|OS|Debian Version|ハードウェア|無線機|
|:---|:---|:---|:---|
|Raspberry Pi OS (32-bit) 2025-12-04|Debian 13 (Trixie)|Raspberry Pi 4 Model B|ICOM ID-52|
|Raspberry Pi OS (32-bit) 2025-12-04|Debian 13 (Trixie)|Raspberry Pi 3 Model B|ICOM ID-52|
|Raspberry Pi OS (32-bit) Lite 2025-12-04|Debian 13 (Trixie)|Raspberry Pi 3 Model B|ICOM ID-52|

※テストは、ICOM ID-52をラズパイとUSB通信ケーブルで接続して行っています。

## 🚀 使い方

0. OSがLite版の場合、最初にgitをインストールしておきます。
   ```bash
   sudo apt install git
   ```

1. 本リポジトリを適当なディレクトリにclone (またはスクリプトをダウンロード) し、ディレクトリに移動します。
   ```bash
   git clone https://github.com/mah-jp/dmonitor-trixie-installer.git
   cd dmonitor-trixie-installer
   ```

2. **ステップ1: パッチ適用済みdebパッケージの構築**
   ```bash
   bash ./1_rebuild_deb.sh
   ```
   > 実行が完了すると、カレントディレクトリに`dmonitor_02.00+patched1_armhf.deb`といった名前で再構築されたパッケージが生成されます。

3. **ステップ2: 対象パッケージのインストール**
   ```bash
   bash ./2_install_patched-deb.sh
   ```
   > 先ほど作成されたばかりの独自の`dmonitor`パッケージを自動判別してインストールが進みます。併せて`WiringPi`の最新版も導入されます。(途中で`apt`コマンドによるパスワードを求められる場合があります。)
   >
   > 💡 **オプション:** すでに同バージョンのパッチ版がインストール済みの環境で、強制的に上書きインストール (再インストール) を行いたい場合は `--reinstall` を付与して実行してください。
   > ```bash
   > bash ./2_install_patched-deb.sh --reinstall
   > ```

4. セットアップが終わったら、設定を反映するためにOSを再起動してください。
   ```bash
   sudo reboot
   ```

5. OS再起動後、ブラウザからdmonitorのURLにアクセスして動作確認を行ってください。

## ⚙️ 特徴と技術的なアプローチ

本スクリプトでは、Trixie上で正常動作させるために以下の技術・修正を用いています。

1. **OSバージョンの詐称 (マウント名前空間の利用)**
   `dmonitor`が備えているOSバージョンチェック (「Bookworm以外では起動しない仕様」や「未サポートOSの警告」) を回避します。本体バイナリに直接手を入れることはせず、`systemd`サービス群の`BindReadOnlyPaths`機能や、CGI環境での`unshare -m`コマンドを使った「一時的なマウント空間の分離」を利用。対象のプロセスから見た`/etc/os-release`などだけをBookworm版のダミー情報にすり替えています。

2. **依存ライブラリのパッチ (t64対応)**
   Debian 13 (Trixie) で導入されたTime_t 64-bit移行に伴うライブラリ名変更 (`libssl3` → `libssl3t64`) に対応するため、一時展開したパッケージの`DEBIAN/control`の依存記述 (`Depends`) を動的に置換します。同時に、独自のパッチ版であることが将来の`apt`管理において識別できるよう`Version:`フィールドに`+patched1`などの識別子を自動追記します。

3. **最新のWiringPiの自動解決インストール**
   GPIO制御などに必要な`WiringPi`が標準のリポジトリから提供されていない状況を考慮し、インストール時にGitHub APIを叩いてWiringPiの最新版 (`armhf.deb`) のURLを動的に特定し、自動で取得・インストールします。当方の調査によると、オリジナル版dmonitorのインストール時に共に導入されるWiringPi 2.52は、「Raspberry Pi 4 Model B Rev 1.2」を識別できませんでした。

また、一般的な改善として。

4. **CGIスクリプトの安定化 (Perl置換)**
   一部のCGIスクリプト内に存在する、IPアドレス取得のための`hostname -I`というシェル呼び出し処理を、CGIとしての正規の情報である環境変数`$SERVER_ADDR`を参照するようにPerlスクリプトを使って一括パッチ (`s/…/…/g`) を当てています。

5. **udevルールの追記 (最新無線機への対応)**
   パッケージ再構築の際に、内容物である`99-dstar.rules`に最新のUSBデバイスマッピング設定を追記しています。これにより、オリジナル版の提供時にはサポートされていなかった新しい無線機 (ICOM ID-50とID-52 PLUS) をUSB接続した際にも、自動でシリアルポートとして認識されるようになります。

## ⚠️ 注意事項 (免責事項)

- 本スクリプト群は、個人作成の非公式スクリプトです。JARL D-STAR委員会や`dmonitor`の本来の開発者さまへ、当パッチスクリプトに関する問い合わせ (「Trixieで動かない」等) は絶対に行わないでください。
- パッケージ内部の`DEBIAN/control`の上書きや、システムレベルでのマウント名前空間の詐称などを使用しています。スクリプトがシステムに及ぼす影響を理解した上で、自己責任でご使用ください。
- 将来的に公式からTrixie用の`dmonitor`がリリースされたり、プログラム構成が大幅に変更された場合は、パッチの適用に失敗する可能性が大いにあります。

## 📄 ライセンス

本プロジェクトのリポジトリに含まれるインストーラースクリプト群は、MIT Licenseの条件の下で公開しています。詳細については [LICENSE](LICENSE) ファイルをご覧ください。

> [!NOTE]
> `dmonitor`プログラム本体および関連ファイル等の著作物の権利はJARL D-STAR委員会に帰属します。当スクリプトはインストール補助のみを目的とした非公式のものであり、`dmonitor`本体の著作権やライセンス形態に影響を与えるものではありません。

## 👤 作者

[大久保 正彦 (Masahiko OHKUBO)](https://remoteroom.jp/)
