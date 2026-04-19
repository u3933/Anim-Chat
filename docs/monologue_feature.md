# モノローグ（独り言）機能 実装方針

このドキュメントは `live2d_chat.html` に実装されたアイドル独り言機能の設計・実装方針をまとめたものです。

---

## 概要

ユーザーが一定時間操作しない場合、アバターが自動的に独り言を呟く。呟いた内容は `chatHistory` に追加されるため、ユーザーがそのまま返信して会話を続けられる。

---

## アイドルタイマー

```javascript
// IDLE_TIMEOUT は .env の IDLE_TIMEOUT（秒）から注入。デフォルト300秒
const _IDLE_RAW   = '%%IDLE_TIMEOUT%%';
const IDLE_TIMEOUT = (_IDLE_RAW.startsWith('%%')) ? 300 : (parseInt(_IDLE_RAW) || 300);
```

### リセットタイミング

`resetIdleTimer()` を以下のタイミングで呼ぶ。

- `sendMessage()`（ユーザーのメッセージ送信）
- `speakMonologue()` の末尾（次の独り言タイマーを再セット）
- `setMonologueEnabled(true)` でONにしたとき

### タイマー停止

- `setMonologueEnabled(false)` のとき `clearTimeout(idleTimer)`
- 現在 TTS 再生中の場合: `speakMonologue()` の先頭で `resetIdleTimer()` を呼んで先送り

---

## .env 設定

```
IDLE_TIMEOUT=300    # 秒単位。デフォルト: 300秒（5分）
```

---

## ストック管理

独り言テキストを事前にLLMで生成してストックしておく方式（リアルタイム生成しない）。

```javascript
const MONOLOGUE_STOCK_MAX = 8;   // ストック上限
const MONOLOGUE_STOCK_MIN = 2;   // この件数以下になったら補充トリガー
const MONOLOGUE_GEN_COUNT = 6;   // 1回の生成件数
```

### 補充トリガー

`speakMonologue()` 内でストック件数を確認し、`MONOLOGUE_STOCK_MIN` 以下なら `generateMonologueStock(false)` を非同期実行（2秒遅延）。

```javascript
if (monologueStock.length <= MONOLOGUE_STOCK_MIN && !isGeneratingMonologue) {
  setTimeout(() => generateMonologueStock(false), 2000);
}
```

### フォールバック

ストックが空のときはハードコードされたフォールバック文を使用（LLM呼び出し不要）。

```javascript
const FALLBACK_MONOLOGUES = [
  'なんか静かだね。こういう時間も悪くないかな。',
  'ちょっとぼーっとしてたよ。何か話したいことあったら気軽に声かけてね。',
  'ふと思ったんだけど、最近どんな感じ？',
];
```

---

## シナリオ生成（`generateMonologueStock`）

### プロンプト設計

```
あなたは「ひより」という名前の明るく元気なAIアシスタントです。
以下のテーマを参考に、ひよりが一人でつぶやく独り言を{count}件生成してください。

テーマ（適宜選んで使用）:
・{theme1}
・{theme2}
・{theme3}

【出力形式（厳守）】
・1行につき1件のみ
・番号・記号・話者名不要
・2〜3文程度、ひよりらしい自然なタメ口
・絵文字・記号不使用
・ユーザーへの呼びかけなし（独り言）
・{count}件、それぞれ異なる話題
```

- **temperature**: 0.9（バリエーション重視）
- **maxOutputTokens**: 800

### Gemini 専用: Google Search グラウンディング

Geminiの場合は**常に**Google Searchグラウンディングを有効化する（最新の時事・季節情報を反映させるため）。

```javascript
if (LLM_PROVIDER === 'gemini') {
  body.tools = [{ googleSearch: {} }]; // groundingEnabled の状態に関わらず常に有効
}
```

### レスポンスのパース

```javascript
const lines = responseText
  .split(/\r?\n/)
  .map(l => l.trim())
  .filter(l =>
    l.length > 5 &&
    !l.startsWith('・') &&
    !l.startsWith('-') &&
    !l.match(/^[\d]+[\.．]/)  // 番号付きリスト除去
  );
```

---

## 発話処理（`speakMonologue`）

```javascript
async function speakMonologue() {
  if (isSpeaking) { resetIdleTimer(); return; } // TTS中は先送り
  if (!live2dModel) { resetIdleTimer(); return; }

  // ストックから1件取り出す
  const line = monologueStock.length > 0
    ? monologueStock.shift()
    : FALLBACK_MONOLOGUES[Math.floor(Math.random() * FALLBACK_MONOLOGUES.length)];

  addMsg('ai', line);
  chatHistory.push({ role: 'model', parts: [{ text: line }] });
  updateLastConvoTime(); // メール生成タイマー用
  resetMailIdleTimer();

  // TTS 再生（アニメON/OFFで分岐）
  const chunks = splitTextForTTS(cleanForTTS(line));
  if (animEnabled) {
    callLLMAnimChunks('', line, chunks)
      .then(codes => playTTSWithLipSync(line, codes))
      .catch(() => playTTSWithLipSync(line, []));
  } else {
    playTTSWithLipSync(line, []);
  }

  // ストック補充チェック
  if (monologueStock.length <= MONOLOGUE_STOCK_MIN && !isGeneratingMonologue) {
    setTimeout(() => generateMonologueStock(false), 2000);
  }

  resetIdleTimer(); // 次のアイドルタイマーをセット
}
```

---

## ストレージ

| キー | 内容 |
|---|---|
| `hiyori_monologue_themes` | テーマ配列（`localStorage`） |
| `hiyori_monologue_stock` | ストック中の独り言配列（`localStorage`） |

### デフォルトテーマ

```javascript
const DEFAULT_MONOLOGUE_THEMES = [
  '最近の天気や季節の話題',
  '美味しい食べ物・飲み物のこと',
  'おすすめのアニメ・音楽・趣味',
];
```

---

## 状態変数

```javascript
let monologueEnabled      = false;
let monologueThemes       = [];
let monologueStock        = [];
let idleTimer             = null;
let isGeneratingMonologue = false;
```

---

## UI

- 設定パネルの「独り言 OFF/ON」ボタンでON/OFF切替
- 「独り言設定」ボタンでモーダルを開き、テーマ編集・ストック確認・今すぐ生成が可能
- モーダルにアイドル時間（秒）とストック件数を表示
