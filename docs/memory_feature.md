# メモリ機能 実装方針

このドキュメントは `live2d_chat.html` に実装された長期記憶（メモリ）機能の設計・実装方針をまとめたものです。
新規コード生成時の参考資料として使用してください。

---

## 概要

会話から重要な情報をLLMで自動抽出し、IndexedDB に永続保存する。
次回以降の会話ではシステムプロンプトにメモリを注入することで、ユーザーの好みや経歴を踏まえた一貫性のある返答を実現する。

---

## ストレージ

| 項目 | 値 |
|---|---|
| ストレージ種別 | IndexedDB |
| DB名 | `hiyori_memory_db` |
| ストア名 | `memories` |
| 上限件数 | 100件（超えたら最古エントリを自動削除） |

### メモリエントリのスキーマ

```json
{
  "id": 1,
  "category": "好み",
  "subject": "コーヒーが好き",
  "summary": "ユーザーはブラックコーヒーを好む。特に朝の一杯を大切にしている。",
  "keywords": ["コーヒー", "朝", "ブラック"],
  "createdAt": "2025-01-01T00:00:00.000Z",
  "lastAccessedAt": "2025-01-05T12:00:00.000Z"
}
```

### カテゴリ一覧

`人物` / `好み` / `経験` / `仕事` / `関係` / `場所` / `その他`

### IndexesDB インデックス

- `category`（検索・フィルタ用）
- `createdAt`（作成日ソート用）
- `lastAccessedAt`（最終アクセス日ソート用・プロンプト注入の優先順位に使用）

---

## CRUD 関数

すべて `async` で、`memoryDB` が `null` の場合は早期リターン。

| 関数 | 役割 |
|---|---|
| `initMemoryDB()` | IndexedDB を開く・スキーマ作成 |
| `_getAllMemories()` | 全件取得 |
| `_addMemory(mem)` | 追加（上限超過時は最古を削除してから追加） |
| `_updateMemory(id, updates)` | 部分更新（`lastAccessedAt` を自動更新） |
| `_deleteMemory(id)` | 1件削除 |
| `_searchMemories(query, category)` | キーワード・カテゴリでフィルタ |

---

## 自動抽出トリガー

- `sendMessage()` 内でターンカウンタ `memoryTurnCount` をインクリメント
- **4ターンごと**に `extractAndSaveMemories(false)` を非同期実行（1.5秒遅延）
- ユーザーはモーダルから手動抽出も可能（`extractAndSaveMemories(true)`）

```javascript
memoryTurnCount++;
if (memoryEnabled && memoryTurnCount % 4 === 0) {
  setTimeout(() => extractAndSaveMemories(false), 1500);
}
```

---

## 抽出プロンプト設計

- **言語**: 英語プロンプト（JSON出力の安定性向上のため）
- **temperature**: 0.3（低め・一貫性重視）
- **maxOutputTokens**: 1000
- **入力**: 直近8メッセージ（chatHistory の末尾8件） + 既存メモリ上位20件のサマリ
- **出力形式**: JSON配列のみ（説明文なし）

### 出力スキーマ

```json
[
  {
    "action": "create",
    "id": null,
    "category": "好み",
    "subject": "短いタイトル（日本語）",
    "summary": "詳細サマリ（日本語）",
    "keywords": ["キーワード1", "キーワード2"]
  },
  {
    "action": "update",
    "id": 5,
    "category": "好み",
    "subject": "既存エントリのタイトル",
    "summary": "マージ・拡張したサマリ（日本語）",
    "keywords": ["キーワード1"]
  }
]
```

- `action: "create"` → `_addMemory()` で新規追加
- `action: "update"` → `_updateMemory(id, ...)` で既存を更新
- 新情報がなければ `[]` を返させる
- パース: `responseText.match(/\[[\s\S]*\]/)` でJSON部分を抽出（コードブロック除去不要）

---

## システムプロンプトへの注入

`buildMemoryContext()` がシステムプロンプトの末尾に追記する文字列を返す。

```javascript
async function buildMemoryContext() {
  if (!memoryEnabled || !memoryDB) return '';
  const all = await _getAllMemories();
  if (all.length === 0) return '';
  // lastAccessedAt 降順で上位20件をプロンプトに注入
  const sorted = all.sort((a,b) =>
    new Date(b.lastAccessedAt) - new Date(a.lastAccessedAt)
  ).slice(0, 20);
  return '\n\n【ユーザーに関する記憶】\n' +
    sorted.map(m => `- ${m.subject}: ${m.summary}`).join('\n');
}
```

呼び出し箇所: `callGeminiChat()` および `callOpenAIChat()` の両方でシステムプロンプト構築時に呼ぶ。

```javascript
const memCtx = await buildMemoryContext();
// Gemini
system_instruction: { parts: [{ text: CHAT_SYSTEM_PROMPT + memCtx }] }
// OpenAI-compatible
{ role: 'system', content: CHAT_SYSTEM_PROMPT + memCtx }
```

---

## 状態変数

```javascript
const MEMORY_DB_NAME  = 'hiyori_memory_db';
const MEMORY_LIMIT    = 100;
let   memoryDB        = null;   // IndexedDB インスタンス
let   memoryEnabled   = true;   // ON/OFFフラグ
let   memoryTurnCount = 0;      // 4ターンごとの自動抽出カウンタ
```

---

## 初期化フロー

```
ページロード
  → initMemoryDB()        // IndexedDB を開く
  → loadModel()           // Live2D モデル読み込み（並列で問題なし）
  → （モデル読み込み完了後）buildMemoryContext() が各LLM呼び出し時に自動実行
```

---

## UI（メモリモーダル）

- 設定パネルの「メモリ」ボタンで開閉
- 機能: カテゴリフィルタ・キーワード検索・手動抽出・手動追加・編集・削除・全削除
- エクスポート/インポート: JSON形式（Gist同期の対象にも含まれる）
- 表示ソート: `lastAccessedAt` 降順

---

## Gist 同期との連携

セッションデータをGist保存する際、メモリも対象に含める。

```javascript
// 保存時
const memories = await _getAllMemories().catch(() => []);
// 復元時：既存を全削除してから追加
const existing = await _getAllMemories();
for (const m of existing) await _deleteMemory(m.id);
for (const m of data.memories) await _addMemory(m);
```

---

## 注意事項

- `memoryDB` が `null` のまま操作しないよう、各CRUD関数の先頭で必ずガードする
- メモリ抽出はバックグラウンド非同期（TTS・アニメ再生をブロックしない）
- Gemini / OpenAI-compatible 両方に対応（プロバイダ分岐は `LLM_PROVIDER` 変数で判定）
- 画像添付（inlineData）はメモリ抽出の対象外（テキスト部分のみ）
