# Gist同期（クラウド保存・復元）実装方針

このドキュメントは `live2d_chat.html` に実装されたGitHub Gistを使ったクロスデバイスセッション同期の設計・実装方針をまとめたものです。

---

## 概要

会話履歴・メモリ・設定をGitHub Gistに保存し、別のブラウザ・デバイスで復元できる。ローカルファイルへのエクスポート/インポートも同じセッションデータ形式を共有する。

---

## GitHub PAT（Personal Access Token）要件

| 項目 | 値 |
|---|---|
| トークン種別 | Fine-grained PAT |
| Repository access | Public repositories（変更不要） |
| Permissions | Account → **Gists: Read and write** のみ |

トークンは `localStorage` に保存（`hiyori_gist_token`）。ページをまたいで再入力不要。

---

## セッションデータ構造

```json
{
  "version": 1,
  "savedAt": "2025-01-01T00:00:00.000Z",
  "localStorage": {
    "hiyori_chat_history":      "...",
    "hiyori_avatar_transform":  "...",
    "hiyori_layout":            "...",
    "hiyori_controls":          "...",
    "hiyori_monologue_themes":  "..."
  },
  "memories": [
    {
      "category": "好み",
      "subject": "コーヒーが好き",
      "summary": "...",
      "keywords": ["コーヒー"],
      "createdAt": "...",
      "lastAccessedAt": "..."
    }
  ]
}
```

### 同期対象の localStorage キー（`LS_SYNC_KEYS`）

```javascript
const LS_SYNC_KEYS = [
  HISTORY_KEY,           // 'hiyori_chat_history'
  TRANSFORM_KEY,         // 'hiyori_avatar_transform'
  LAYOUT_KEY,            // 'hiyori_layout'
  CONTROLS_KEY,          // 'hiyori_controls'
  MONOLOGUE_THEMES_KEY,  // 'hiyori_monologue_themes'
  MAIL_INBOX_KEY,        // 'hiyori_mail_inbox'
  // wizard config (新デバイスでの設定移行用)
  'hiyori_cfg_llm_provider',
  'hiyori_cfg_gemini_model',                              // APIキーは除外（セキュリティ）
  'hiyori_cfg_llm_base_url',   'hiyori_cfg_llm_model',   // LLM APIキーも除外
  'hiyori_cfg_tts_provider',   'hiyori_cfg_tts_endpoint',
  'hiyori_cfg_tts_model',      'hiyori_cfg_tts_speaker_id', 'hiyori_cfg_tts_volume',
  'hiyori_cfg_chat_title',     'hiyori_cfg_system_prompt',
  'hiyori_theme_vars',
];
```

### 同期対象外（意図的な除外）

| データ | 理由 |
|---|---|
| 背景・前景の画像（IndexedDB の Blob） | サイズが大きくGistに格納不可 |
| TTS自動かな辞書キャッシュ | 軽量かつデバイス固有で再生成可能 |
| Gist トークン自体 | セキュリティ上の理由 |
| Gemini / LLM APIキー | Gistに保存するとクラウド流出リスクあり。localStorageには保存してよい（同一オリジン制限のため） |

---

## データ収集（`_gatherSessionData`）

```javascript
async function _gatherSessionData() {
  const ls = {};
  for (const key of LS_SYNC_KEYS) {
    const val = localStorage.getItem(key);
    if (val !== null) ls[key] = val;
  }
  const memories = await _getAllMemories().catch(() => []);
  return { version: 1, savedAt: new Date().toISOString(), localStorage: ls, memories };
}
```

---

## Gist API 呼び出し

### 保存（`gistSave`）

```
# 初回（Gist ID未入力）
POST https://api.github.com/gists
Authorization: Bearer {token}
{
  "description": "hiyori-chat session",
  "public": false,
  "files": { "hiyori_session.json": { "content": "..." } }
}

# 2回目以降（Gist IDあり）
PATCH https://api.github.com/gists/{gistId}
Authorization: Bearer {token}
{
  "files": { "hiyori_session.json": { "content": "..." } }
}
```

保存後、レスポンスの `result.id` を `localStorage` と UIの入力欄に保存する。

### 復元（`gistRestore`）

```
GET https://api.github.com/gists/{gistId}
Authorization: Bearer {token}
```

**truncate対応**: Gistファイルが大きい場合 `fileObj.truncated === true` になる。その場合は `fileObj.raw_url` から全文を再取得する。

```javascript
const rawContent = fileObj.truncated
  ? await (await fetch(fileObj.raw_url)).text()
  : fileObj.content;
```

---

## データ適用（`_applySessionData`）

```javascript
async function _applySessionData(data) {
  if (!data || data.version !== 1) throw new Error('不正なセッションデータです');

  // localStorage を上書き
  for (const [key, val] of Object.entries(data.localStorage || {})) {
    localStorage.setItem(key, val);
  }

  // メモリを全削除してから追加（マージではなく上書き）
  if (Array.isArray(data.memories) && memoryDB) {
    const existing = await _getAllMemories();
    for (const m of existing) await _deleteMemory(m.id);
    for (const m of data.memories) await _addMemory({ ...m });
  }
}
```

### 復元後の反映タイミング

| データ | 反映タイミング |
|---|---|
| メモリ | 即時（`updateMemoryDisplay()` を呼ぶ） |
| 会話履歴・設定 | **ページリロード後**（localStorage に書き込み済みのためリロードで読み込まれる） |

---

## ローカルファイルとの互換性

`sessionExport` / `sessionImport` は `_gatherSessionData` / `_applySessionData` を共用するため、Gistの保存ファイルとローカルJSONファイルは同じ形式。

```
ローカルエクスポート → hiyori_session_2025-01-01.json
                         ↓ 別デバイスで
ローカルインポート  → _applySessionData()
         （または Gistに手動アップして gistRestore してもOK）
```

---

## ストレージキー

```javascript
const GIST_TOKEN_KEY = 'hiyori_gist_token'; // PAT
const GIST_ID_KEY    = 'hiyori_gist_id';    // Gist ID
const GIST_FILENAME  = 'hiyori_session.json';
```

---

## UIの配置

### チャット画面（メモリモーダル内「☁️ Gist同期」）

| 操作 | 内容 |
|---|---|
| ☁️ 保存 | ID未入力時は新規作成、入力済みは上書き更新 |
| ☁️ 復元 | Gist IDを指定して上書き復元 |
| コピー | Gist IDをクリップボードにコピー |
| 💾 セッション保存 | ローカルJSONファイルにダウンロード |
| 📂 セッション読込 | ローカルJSONファイルから復元 |

### ウィザード画面（先頭「☁️ Gistから設定を復元」）

新デバイス（ブラウザPC・スマホ）で初めてウィザードを開いたとき、Gist IDとトークンを入力して復元ボタンを押すと、`hiyori_cfg_*` / `hiyori_theme_vars` をlocalStorageに書き込み、ウィザードの入力欄を自動更新する。

- トークンとGist IDはlocalStorageに保存（次回以降入力不要）
- 復元後はウィザードで確認・変更してから「チャット画面を開く」を押すだけ
