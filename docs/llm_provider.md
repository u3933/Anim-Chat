# LLMプロバイダー抽象化 実装方針

このドキュメントは `live2d_chat.html` に実装されたGemini / OpenAI互換デュアルプロバイダー構成の設計・実装方針をまとめたものです。

---

## プロバイダー選択

`.env` の `LLM_PROVIDER` で選択する。`chat_start.ps1` が `%%LLM_PROVIDER%%` プレースホルダーに注入。

```javascript
const LLM_PROVIDER = '%%LLM_PROVIDER%%'; // 'gemini' | 'openai'
```

| 値 | 対象 |
|---|---|
| `gemini` | Google Gemini API（デフォルト） |
| `openai` | OpenAI・Ollama・LM Studio・llama.cpp などOpenAI互換エンドポイント全般 |

---

## 設定変数（.envから注入）

```javascript
// Gemini
const GEMINI_API_KEY = '%%GEMINI_API_KEY%%';
const GEMINI_MODEL   = '%%GEMINI_MODEL%%';   // 例: gemini-2.0-flash

// OpenAI-compatible
const LLM_BASE_URL   = '%%LLM_BASE_URL%%';  // 例: http://localhost:11434/v1
const LLM_API_KEY    = '%%LLM_API_KEY%%';   // ローカルLLMは空文字でOK
const LLM_MODEL      = '%%LLM_MODEL%%';     // 例: gpt-4o, llama3
```

---

## 共通ラッパーパターン

すべてのLLM呼び出しは **共通ラッパー関数** 経由でプロバイダーを分岐する。呼び出し元はプロバイダーを意識しない。

```javascript
async function callLLMChat(userMessage) {
  lastSearchQueries = null;
  return LLM_PROVIDER === 'openai'
    ? callOpenAIChat(userMessage)
    : callGeminiChat(userMessage);
}

async function callLLMAnimChunks(userMessage, aiResponse, chunks) {
  return LLM_PROVIDER === 'openai'
    ? callOpenAIAnimChunks(userMessage, aiResponse, chunks)
    : callGeminiAnimChunks(userMessage, aiResponse, chunks);
}
```

その他の機能（モノローグ生成・メール生成・メモリ抽出・TTS自動かな変換）でも同じパターンで分岐する。

---

## Gemini API 呼び出し仕様

### エンドポイント

```
POST https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={GEMINI_API_KEY}
```

### リクエスト構造

```json
{
  "system_instruction": { "parts": [{ "text": "システムプロンプト" }] },
  "contents": [
    { "role": "user",  "parts": [{ "text": "..." }] },
    { "role": "model", "parts": [{ "text": "..." }] }
  ],
  "generationConfig": { "temperature": 0.85, "maxOutputTokens": 300 },
  "tools": [{ "googleSearch": {} }]
}
```

- `role` は `user` / `model`（OpenAIの `assistant` ではない）
- システムプロンプトは `system_instruction` フィールド（`contents` 配列に含めない）
- Google Search グラウンディングは `tools: [{ googleSearch: {} }]` で有効化

### レスポンス取得

```javascript
data.candidates?.[0]?.content?.parts?.[0]?.text
// グラウンディングの検索クエリ
data.candidates?.[0]?.groundingMetadata?.webSearchQueries
```

### JSON出力を要求する場合

```javascript
generationConfig: {
  temperature: 0.1,
  responseMimeType: 'application/json'
}
```

---

## OpenAI互換 API 呼び出し仕様

### エンドポイント

```
POST {LLM_BASE_URL}/chat/completions
```

### リクエスト構造

```json
{
  "model": "モデル名",
  "messages": [
    { "role": "system",    "content": "システムプロンプト" },
    { "role": "user",      "content": "..." },
    { "role": "assistant", "content": "..." }
  ],
  "temperature": 0.85
}
```

- `role` は `user` / `assistant`（Geminiの `model` ではない）
- システムプロンプトは最初の `role: "system"` メッセージ

### chatHistory の変換

Gemini形式（`role: 'model'`）をOpenAI形式（`role: 'assistant'`）に変換して渡す。

```javascript
chatHistory.slice(-(MAX_HISTORY * 2)).map(m => ({
  role: m.role === 'model' ? 'assistant' : 'user',
  content: m.parts[0].text,
}))
```

### APIキーが不要な場合（ローカルLLM）

```javascript
const headers = { 'Content-Type': 'application/json' };
if (LLM_API_KEY) headers['Authorization'] = `Bearer ${LLM_API_KEY}`;
```

`LLM_API_KEY` が空文字のとき `Authorization` ヘッダーを付けない。

### レスポンス取得

```javascript
data.choices?.[0]?.message?.content
```

### JSON出力を要求する場合

コードブロックを返すモデルがあるため、除去してからパースする。

```javascript
text = text.replace(/```(?:json)?\n?/g, '').replace(/```/g, '').trim();
result = JSON.parse(text);
```

---

## 生成パラメータ（用途別）

| 用途 | temperature | maxOutputTokens | 備考 |
|---|---|---|---|
| チャット返答 | 0.85 | 300 | 自然な会話 |
| 表情コード生成 | 0.4 | 1200 | 安定したJSON出力 |
| モノローグ生成 | 0.9 | 800 | バリエーション重視 |
| メモリ抽出 | 0.3 | 1000 | 精度重視 |
| メール生成 | 0.8 | 200 | 短文・自然文 |
| TTS自動かな変換 | 0.1 | — | 一貫性重視 |

---

## AbortController（生成中断）

チャット返答のLLM呼び出しにはAbortControllerのシグナルを渡す。送信ボタンが「■」中断ボタンになる。

```javascript
let chatAbortController = null;

// 送信時
chatAbortController = new AbortController();
// fetch に渡す
{ ..., signal: chatAbortController?.signal }

// 中断時
function abortChat() {
  if (chatAbortController) chatAbortController.abort();
}

// catch で区別
if (e.name === 'AbortError') {
  addMsg('sys', '中断しました');
} else {
  addMsg('sys', 'エラー: ' + e.message);
}
```

AbortControllerはチャット返答のみに適用。モノローグ・メール・メモリ抽出などのバックグラウンド処理には不使用。

---

## Gemini 専用機能

| 機能 | 実装 |
|---|---|
| Google Search グラウンディング | `tools: [{ googleSearch: {} }]` |
| グラウンディング検索クエリの表示 | `groundingMetadata.webSearchQueries` を `addMsg('sys', ...)` で表示 |
| JSON強制出力 | `responseMimeType: 'application/json'` |

グラウンディングはチャット返答（ユーザーがONにした場合）とモノローグ生成（常に有効）で使用する。

---

## プレースホルダー注入フロー

```
.env
  → chat_start.ps1 が読み込み
      → live2d_chat.html の %%PLACEHOLDER%% を置換
          → live2d_chat_dev.html（API キーを含む実行ファイル）
```

プレースホルダーが未置換のとき（`file://` で直接開いた等）はデフォルト値にフォールバックする。

```javascript
const _IDLE_RAW    = '%%IDLE_TIMEOUT%%';
const IDLE_TIMEOUT = (_IDLE_RAW.startsWith('%%')) ? 300 : (parseInt(_IDLE_RAW) || 300);
```
