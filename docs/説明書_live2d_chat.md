# Anim Chat — Live2D版 操作マニュアル

> ファイル: `live2d_chat.html`

---

## 目次

1. [フォルダー構造](#フォルダー構造)
2. [必要環境](#必要環境)
3. [セットアップ・起動方法](#セットアップ起動方法)
4. [初回設定（ウィザード）](#初回設定ウィザード)
5. [操作説明](#操作説明)
6. [アーキテクチャ](#アーキテクチャ)
7. [トラブルシューティング](#トラブルシューティング)

---

## フォルダー構造

```
svg_anim_test/
├── live2d_chat.html          # Live2D版チャットアプリ本体
├── wizard.html               # セットアップウィザード
├── start.bat                 # Windows 起動スクリプト（ダブルクリック可）
├── start.command             # macOS 起動スクリプト（ダブルクリック可）
├── start.sh                  # macOS / Linux 起動スクリプト
├── miniserve.exe             # Windows 用 HTTP サーバー（同梱）
├── miniserve-mac             # macOS 用 HTTP サーバー（同梱）
├── manifest.json             # PWA マニフェスト
├── tts_dict.yaml             # TTS 読み替え辞書（固有名詞など）
├── assets/                   # Live2D モデルデータ
│   ├── hiyori_pro_t11.model3.json
│   ├── hiyori_pro_t11.moc3
│   ├── hiyori_pro_t11.physics3.json
│   └── hiyori_pro_t11.2048/  # テクスチャ
├── knowledge/                # ナレッジベース（.txt / .md ファイルを配置）
├── knowledge_manifest.json   # ナレッジ読込リスト（自動生成）
├── docs/                     # ドキュメント類
└── CubismWebSamples-5-r.5/  # Live2D Cubism Web SDK
```

> `knowledge/` に `.txt` または `.md` ファイルを置くと、AIが会話の参考にします。

---

## 必要環境

| 項目 | 要件 |
|---|---|
| ブラウザ | Chrome / Edge 最新版推奨（Safari は部分的に動作） |
| LLM API | Google Gemini API キー **または** OpenAI 互換エンドポイント |
| TTS（任意） | Style-Bert-VITS2 または VOICEVOX をローカルで起動済み |
> Node.js のインストールは不要です。HTTP サーバー（miniserve）を同梱しています。

---

## セットアップ・起動方法

### Windows

1. `start.bat` をダブルクリック
   - 同梱の `miniserve.exe` によりローカルHTTPサーバー（ポート 3000）を起動
   - ブラウザが `http://localhost:3000/wizard.html` を自動で開く
2. ウィザードで「起動モード」を **静止画版** に切り替えて「チャット画面を開く →」

> **Windows SmartScreen 警告が出た場合**: 「詳細情報」→「実行」をクリックして許可してください。

### macOS

1. `start.command` をダブルクリック
   - 同梱の `miniserve-mac` によりローカルHTTPサーバー（ポート 3000）を起動
   - ブラウザが `http://localhost:3000/wizard.html` を自動で開く
2. ウィザードで「起動モード」を **静止画版** に切り替えて「チャット画面を開く →」

> **「開発元を確認できない」警告が出た場合**: システム環境設定 → プライバシーとセキュリティ → 「このまま開く」をクリックしてください。

### Linux

```bash
chmod +x start.sh
./start.sh
```

### 手動起動

```bash
# Windows
miniserve.exe --port 3000 .

# macOS
./miniserve-mac --port 3000 .

# Linux
./miniserve-mac --port 3000 .
```

ブラウザで `http://localhost:3000/wizard.html` を開く。

ウィザードを経由せず直接開く場合（設定済みの場合）:
```
http://localhost:3000/illust_chat.html
```

> **重要**: `file://` プロトコルでは Live2D モデルや IndexedDB が正しく動作しません。必ずローカルHTTPサーバー経由で開いてください。

---

## 初回設定（ウィザード）

`wizard.html` を開くと以下のセクションが表示されます。

### 1. LLM（AI）設定

| プロバイダー | 設定内容 |
|---|---|
| **Gemini（Google）** | Gemini API キー + モデル名（例: `gemini-2.0-flash`） |
| **OpenAI 互換** | ベースURL（例: `http://localhost:11434/v1`）+ APIキー（ローカルは空欄可）+ モデル名 |

### 2. 音声合成（TTS）設定

| プロバイダー | 設定内容 |
|---|---|
| **Style-Bert-VITS2** | エンドポイント（デフォルト: `http://127.0.0.1:5000`）+ モデルフォルダ名 |
| **VOICEVOX** | エンドポイント（デフォルト: `http://127.0.0.1:5000`）+ スピーカーID |
| **TTS なし** | 音声なしでテキストのみ動作 |

「▶ テスト再生」ボタンで設定を確認できます。

### 3. キャラクター設定

- **アプリタイトル**: ブラウザタブとヘッダーに表示
- **システムプロンプト**: AIキャラクターの人格・設定（空欄でデフォルト使用）

### 4. 外観設定

ダーク系・ライト系のカラーテーマを選択。

### 起動モード選択

- **Live2D版** ← このファイル
- **静止画版** → `illust_chat.html` が開く

「チャット画面を開く →」で設定を保存して起動します。

---

## 操作説明

### 基本チャット

| 操作 | 内容 |
|---|---|
| テキスト入力 → Enter / 送信ボタン | AIにメッセージを送信 |
| ■ 中断ボタン | 生成中のAI返答を中断 |
| Shift+Enter | 改行（送信しない） |

AIの返答と同時に Live2D キャラクターが表情・モーションを変化させます。

### Live2D アバター操作

| 操作 | 内容 |
|---|---|
| アバターをドラッグ | 位置を移動 |
| スクロール（アバター上） | サイズ変更 |
| 設定パネル → 「位置リセット」 | 初期位置・サイズに戻す |
| 設定パネル → 「アニメ ON/OFF」 | アニメーション一時停止 |

### 設定パネル（設定 ▼）

- **TTS ON/OFF**: 音声合成の有効・無効切り替え
- **Grounding ON/OFF**: Gemini の Google 検索グラウンディング（Gemini のみ）
- **背景・前景画像**: 任意の画像を IndexedDB に保存して表示

### メール機能（📪 メール）

AIが会話の流れで生成するショートメール。受信時はアイコンが 📬 に変化。未読件数バッジで通知。

### メモリ機能

会話から自動的にユーザーの情報・好みを抽出・保存。メモリモーダルで確認・削除できます。Gist同期でクロスデバイス共有が可能。

### モノローグ機能

一定時間操作がないとき（デフォルト5分）、キャラクターが自動で独り言を発します。

### ナレッジベース

`knowledge/` フォルダに `.txt` / `.md` ファイルを置くと、AIが返答の参考にします。キャラクター設定・世界観・FAQ などを記述できます。

### Gist 同期（☁️）

GitHub Personal Access Token と Gist ID を使って、会話履歴・メモリ・設定を別デバイスと共有できます。詳細は [gist_sync.md](gist_sync.md) を参照。

### レイアウト切り替え

ヘッダーの「モバイル / PC表示」ボタンでレイアウトを切り替えます。

---

## アーキテクチャ

### 全体構成

```
ブラウザ（単一HTMLファイル）
├── Live2D Cubism SDK（CubismWebSamples-5-r.5/）
│     └── WebGL + Canvas でアバター描画
├── LLM API（Gemini / OpenAI互換）
│     ├── チャット返答
│     ├── 表情・アニメーションコード生成
│     ├── モノローグ生成
│     ├── メモリ抽出
│     └── メール生成
├── TTS API（SBV2 / VOICEVOX）
│     └── 音声 → AudioContext で再生 → 口パク連動
├── localStorage
│     └── 設定・会話履歴・レイアウト・テーマ
├── IndexedDB
│     └── 背景・前景画像 Blob / メモリDB
└── GitHub Gist API（任意）
      └── セッション同期
```

### LLM 呼び出しフロー（チャット）

```
sendMessage()
  ↓
callLLMChat(userMsg)          ← チャット返答（最大300トークン）
  ↓
[返答テキスト]
  ↓
callLLMAnimChunks(...)        ← 表情・モーションコード生成（並行）
  ↓
アニメーション再生 + TTS再生
```

### 表情・アニメーション

AIが返答テキストをもとにパラメータ（`PARAM_ANGLE_X`, `PARAM_EYE_L_OPEN` など）を JSON で生成し、Cubism SDK に適用します。詳細は [expression_animation.md](expression_animation.md) を参照。

### TTS 再生フロー

```
テキストをチャンク分割（句読点・改行）
  ↓
各チャンク → TTS API → ArrayBuffer
  ↓
AudioContext.decodeAudioData()
  ↓
BufferSource.start() + 口パク（PARAM_MOUTH_OPEN_Y 操作）
```

---

## トラブルシューティング

### Live2D モデルが表示されない

- `file://` で開いていないか確認 → `http://localhost:3000/` で開く
- `assets/` フォルダが存在し `hiyori_pro_t11.model3.json` があるか確認
- ブラウザコンソールの WebGL エラーを確認

### AIが返答しない

- ウィザードで API キーが保存されているか確認（ブラウザの DevTools → Application → localStorage → `hiyori_cfg_gemini_api_key`）
- Gemini の場合: API キーが有効で、モデル名が正しいか確認（例: `gemini-2.0-flash`）
- OpenAI互換の場合: エンドポイントにアクセスできるか確認（`curl http://localhost:11434/v1/models` など）
- コンソールに `[Chat]` エラーが出ていれば内容を確認

### TTS が再生されない

- TTS サーバーが起動しているか確認
- エンドポイント URL がウィザードの設定と一致しているか確認
- ウィザードの「▶ テスト再生」でエラーメッセージを確認
- 設定パネルの「TTS ON」になっているか確認

### 「表情・アニメーション」が動かない

- Gemini `thinking` 系モデル使用時は `maxOutputTokens` が不足する場合があります（コンソールで `MAX_TOKENS` エラーを確認）
- OpenAI互換で JSON 出力が安定しない場合は、`function calling` 対応モデルを推奨

### メモリ・Gist が保存されない

- IndexedDB のサイズ制限に達している可能性 → ブラウザのサイトデータを確認
- GitHub PAT の権限が「Gists: Read and write」になっているか確認

### ページリロードで設定がリセットされる

- localStorage がブロックされている（プライベートブラウズモードなど）
- 別のオリジン（ポート番号が変わった等）でアクセスしている

---

*最終更新: 2026-04-20*
