# Anim-Chat — AI チャットアプリ v4.3

Live2D または差分イラストのキャラクターと会話できるローカル動作のAIチャットアプリです。

- **Live2D版** (`live2d_chat.html`) — リアルタイムアニメーション・表情・口パク連動
- **静止画版** (`illust_chat.html`) — 差分イラスト画像を感情に合わせて自動切替

どちらもブラウザ単体で動作し、インストール不要です。AIは Google Gemini またはローカルLLM（Ollama / LM Studio 等）を使用します。

---

## 機能

- AIとのマルチターン会話（会話履歴の永続化・エクスポート）
- 感情に合わせたキャラクター表情変化
- 音声合成（Style-Bert-VITS2 / VOICEVOX 対応）
- 長期記憶（会話から自動抽出・次回以降の会話に反映）
- アイドル独り言（一定時間操作がないとキャラが自動でつぶやく）
- AIからのメール（閉じている間にメールが届く演出）
- ナレッジベース（`knowledge/` フォルダのファイルをAIが参考にする）
- Google検索グラウンディング（Gemini 使用時）
- ファイル添付（画像・テキスト・PDF）
- Gist同期（GitHub Gistでクロスデバイス設定共有）
- カラーテーマ（ダーク5種・ライト6種）
- PWA対応（スマートフォンのホーム画面に追加可能）

---

## 必要なもの

### 必須

| 項目 | 入手先 |
|---|---|
| **LLM API** — 以下のいずれか | |
| &emsp;Google Gemini API キー | https://aistudio.google.com/ |
| &emsp;OpenAI API キー | https://platform.openai.com/ |
| &emsp;ローカルLLM（Ollama / LM Studio 等） | https://ollama.com/ |

### Live2D版を使う場合（別途用意が必要）

Live2D関連ファイルはライセンスの都合上、このリポジトリには含まれていません。以下を各自で取得して配置してください。

| ファイル | 取得先 | 配置場所 |
|---|---|---|
| `live2dcubismcore.min.js` | [Cubism SDK for Web](https://www.live2d.com/download/cubism-sdk/) をダウンロード → `Core/` フォルダ内 | プロジェクトルート |
| Live2D モデルファイル一式 | [Live2D サンプルモデル](https://www.live2d.com/download/sample-data/) から任意のモデルを取得 | `assets/` フォルダ |

> Live2D サンプルモデルおよび Cubism SDK の使用は各利用規約に従ってください。

### TTS（音声合成）を使う場合（任意）

| プロバイダー | 起動方法 |
|---|---|
| **Style-Bert-VITS2** | `python server_fastapi.py --allow-origins='*'` |
| **VOICEVOX** | アプリ起動 → 設定 → エンジン → 「他のソフトウェアからのアクセスを許可する」をON |

---

## セットアップ

### 1. リポジトリをクローン

```bash
git clone https://github.com/<your-repo>.git
cd <repo-name>
```

### 2. 静止画版を使う場合のみ

キャラクターの差分イラスト画像を用意してください。表情ごとに最大10枚（PNG / JPG 推奨）です。

| スロット | 表情の例 |
|---|---|
| 0 | ノーマル（通常） |
| 1 | 嬉しい・楽しい |
| 2 | 悲しい・寂しい |
| 3 | 驚く |
| 4 | 照れる・恥ずかしい |
| 5 | 考えている |
| 6 | 怒っている・不機嫌 |
| 7 | 眠い・疲れている |
| 8〜9 | 任意 |

画像の登録はアプリ起動後に「設定 ▼ → 表情設定」から行います。1枚だけ登録した場合はその画像が常時表示されます。

### 3. Live2D版を使う場合のみ

`assets/` フォルダにモデルファイルを配置し、`live2dcubismcore.min.js` をルートに置いてください。

また、`live2d_chat.html` 内の以下の箇所をモデルのパスに合わせて変更してください（デフォルトは `hiyori_pro_t11`）：

```javascript
const MODEL_PATH = 'assets/hiyori_pro_t11.model3.json';
```

### 4. アプリを起動

**Windows:**
```
start.bat をダブルクリック
```

または:
```powershell
.\start.ps1
```

**macOS:**
```
start.command をダブルクリック
```
または:
```bash
chmod +x start.sh
./start.sh
```

**Linux:**
```bash
chmod +x start.sh
./start.sh
```

ブラウザで `http://localhost:3000/wizard.html` を開きます。

### 5. セットアップウィザードで設定

1. **LLM設定** — APIキーとモデルを入力
2. **TTS設定** — 音声合成プロバイダーを選択（なしでもOK）
3. **キャラクター設定** — タイトル・システムプロンプトを入力（任意）
4. **外観設定** — カラーテーマを選択
5. **起動モード** —「Live2D版」または「静止画版」を選択
6. 「チャット画面を開く →」をクリック

---

## 静止画版の表情設定

静止画版は差分イラストを使った表情切替機能を持っています。用意した画像をアプリ内で登録します。

1. チャット画面 → 設定パネル（設定 ▼）→「表情設定」
2. 各スロット（最大10種類）に差分イラスト画像をアップロード
3. ラベルを編集してAIへの感情ヒントを調整

AIが返答のたびに感情に合ったスロットを自動選択します。

---

## ナレッジベース

`knowledge/` フォルダに `.txt` または `.md` ファイルを置くと、AIが返答の参考にします。

```
knowledge/
├── character.md    ← キャラクター設定・世界観
├── faq.txt         ← よくある質問
└── ...
```

---

## フォルダ構成

```
.
├── live2d_chat.html      # Live2D版チャットアプリ
├── illust_chat.html      # 静止画版チャットアプリ
├── wizard.html           # セットアップウィザード
├── start.bat             # Windows起動スクリプト
├── start.ps1             # Windows PowerShell起動スクリプト
├── start.sh              # macOS/Linux起動スクリプト
├── manifest.json         # PWAマニフェスト
├── tts_dict.yaml         # TTS読み替え辞書
├── images/               # 静止画版表情画像の格納先（各自で用意）
├── knowledge/            # ナレッジベース（ファイルを追加して使用）
├── assets/               # Live2Dモデル（各自で用意）
├── live2dcubismcore.min.js  # Live2D SDK（各自で用意）
└── docs/                 # 詳細ドキュメント
```

---

## 詳細ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/説明書_live2d_chat.md](docs/説明書_live2d_chat.md) | Live2D版 操作マニュアル |
| [docs/説明書_illust_chat.md](docs/説明書_illust_chat.md) | 静止画版 操作マニュアル |
| [docs/gist_sync.md](docs/gist_sync.md) | Gist同期の設定方法 |
| [docs/tts_api.md](docs/tts_api.md) | TTS API仕様 |

---

## ライセンス

本プロジェクトのオリジナルコード（`live2d_chat.html` / `illust_chat.html` / `wizard.html` / 起動スクリプト等）は **MIT License** で提供します。

### 利用規約に注意が必要なもの（このリポジトリには含まれません）

| コンポーネント | 規約 |
|---|---|
| Live2D Cubism SDK | [Cubism SDK 使用許諾契約](https://www.live2d.com/eula/terms_of_use_sdk_jp.html) |
| Live2D サンプルモデル | [サンプルデータ利用規約](https://www.live2d.com/eula/terms_of_use_sample_data_products_jp.html) |
| Style-Bert-VITS2 | Apache License 2.0 |
| VOICEVOX | [VOICEVOX 利用規約](https://voicevox.hiroshiba.jp/term/) |

---

## トラブルシューティング

**ページが開かない / Live2Dが表示されない**
→ `file://` で開かずに `http://localhost:3000/` 経由で開いてください。

**AIが返答しない**
→ ウィザードで入力したAPIキーがブラウザに保存されているか確認（DevTools → Application → localStorage）。

**TTSが再生されない**
→ ウィザードの「▶ テスト再生」でエラーを確認。TTSサーバーが起動しているか確認。

詳細は [docs/説明書_live2d_chat.md](docs/説明書_live2d_chat.md) または [docs/説明書_illust_chat.md](docs/説明書_illust_chat.md) のトラブルシューティング節を参照してください。
