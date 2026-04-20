#!/bin/bash
# start.command — macOS 起動スクリプト（ダブルクリック可）

# このスクリプトのあるフォルダに移動
cd "$(dirname "$0")"

# miniserve-mac に実行権限を付与
chmod +x ./miniserve-mac

# ブラウザを開く（1秒後）
sleep 1 && open http://localhost:3000/wizard.html &

# HTTPサーバー起動
./miniserve-mac --port 3000 .
