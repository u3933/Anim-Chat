# TTS 前処理 実装方針

このドキュメントは `live2d_chat.html` に実装された TTS 送信前処理（テキストクリーニング・辞書置換・かな変換・チャンク分割）の設計・実装方針をまとめたものです。
新規コード生成時の参考資料として使用してください。

---

## 処理パイプライン全体像

```
LLM 返答テキスト
        │
        ▼
cleanForTTS(text)
  ├─ 1. applyTTSDict(text)          手動辞書置換（tts_dict.yaml）
  ├─ 2. extractUnknownEnglish(text) 未知英単語を抽出
  ├─ 3. lookupKanaBackground(words) LLMへ非同期問い合わせ（fire-and-forget）
  ├─ 4. applyTTSAutoDict(text)      自動かな辞書キャッシュを適用
  └─ 5. 記号・絵文字除去・空白正規化
        │
        ▼
splitTextForTTS(text, maxLength=100)
        │
        ▼
chunks[]  → playTTSChunk() × N
```

---

## 1. 手動辞書（tts_dict.yaml）

### ファイル形式

Cafe-Lumiere 互換の YAML形式。

```yaml
words:
  Day: でい
  TikTok: てぃっくとっく
  API: えーぴーあい
  東京大学: とうきょうだいがく
```

### 読み込み（`loadTTSDict`）

- 起動時に `fetch('tts_dict.yaml')` で取得
- `words:` セクション以下の `表記: 読み` 行をパース
- ファイル未存在・fetchエラーは静かに無視
- 設定パネルの「辞書再読込」ボタンで実行時リロード可能（`reloadTTSDict`）

### 適用ルール（`applyTTSDict`）

```javascript
// ASCII系キー（英数字・ハイフン・ピリオドのみ）
//   大文字小文字無視・前後が英数字でない位置でマッチ（単語境界を模倣）
const re = new RegExp('(?<![a-zA-Z0-9])' + escaped + '(?![a-zA-Z0-9])', 'gi');

// 日本語を含むキー
text = text.replaceAll(word, reading);

// 長いキーを優先適用（部分一致の問題を防ぐ）
entries.sort((a, b) => b[0].length - a[0].length);
```

| キー種別 | マッチ方式 | 大小文字 |
|---|---|---|
| ASCII系（英数字・`-`・`.`） | lookbehind/lookahead で単語境界 | 無視（gi フラグ） |
| 日本語を含む | `replaceAll`（完全一致） | 区別あり |

---

## 2. 自動かな変換（LLM）

### 状態変数

```javascript
const TTS_AUTO_DICT_KEY = 'hiyori_tts_auto_dict';
let   TTS_AUTO_DICT     = {};       // インメモリキャッシュ
const ttsPendingWords   = new Set(); // 問い合わせ中の単語（重複リクエスト防止）
```

- `TTS_AUTO_DICT` は起動時に `localStorage` から復元（`loadTTSAutoDict`）
- LLM応答後に `localStorage` へ永続保存（`saveTTSAutoDict`）

### 未知英単語の抽出（`extractUnknownEnglish`）

```javascript
const re = /[a-zA-Z][a-zA-Z0-9\-]*/g;
```

以下のいずれかに該当する単語はスキップ（重複除去）:
- 手動辞書にある（大文字小文字無視で照合）
- 自動キャッシュにある
- `ttsPendingWords` に含まれる（問い合わせ中）

### LLM への問い合わせ（`lookupKanaBackground`）

- **非同期・ノンブロッキング**（`fire-and-forget`）
- 現在の TTS 再生はブロックしない。**次回の発話から**キャッシュが反映される

#### プロンプト

```
以下の英単語・固有名詞を日本語TTSシステム向けのひらがな読みに変換してください。
日本語で一般的に使われるカタカナ読みをひらがなで返してください。
JSON形式のみで出力してください（説明・コードブロック不要）。

変換対象: Day、TikTok、menu

出力例: {"Day": "でい", "TikTok": "てぃっくとっく", "menu": "めにゅー"}
```

#### LLMパラメータ

| 項目 | 値 |
|---|---|
| temperature | 0.1（一貫した読みを生成するため低め） |
| Gemini | `responseMimeType: 'application/json'` を使用 |
| OpenAI互換 | レスポンスのコードブロック（` ```json ` 等）を除去してからパース |

#### キャッシュ保存形式（localStorage）

```json
{
  "day": "でい",
  "tiktok": "てぃっくとっく",
  "api": "えーぴーあい"
}
```

キーはすべて **小文字** で保存（照合時も `toLowerCase()` で統一）。

### 自動辞書の適用（`applyTTSAutoDict`）

- 長いキーを優先適用（手動辞書と同じソート）
- マッチルール: lookbehind/lookahead による単語境界（`gi` フラグ）

### 優先順位

```
手動辞書（tts_dict.yaml）  ＞  自動かな辞書キャッシュ  ＞  未変換のまま（TTS エンジン任せ）
```

手動辞書を上書きしたい場合は `tts_dict.yaml` に追記するだけでよい（自動キャッシュより必ず優先される）。

---

## 3. テキストクリーニング（`cleanForTTS`）

辞書・自動変換の後に以下の正規化を行う。

```javascript
text
  .replace(/[^\w\s。、！？!?\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\u3400-\u4DBFa-zA-Z0-9ー〜～・\u2026]/g, '')
  .replace(/\s+/g, ' ')
  .trim()
```

**残すもの**: ひらがな・カタカナ・漢字・ASCII英数字・基本句読点（`。、！？!?`）・長音符・中点・省略記号  
**除去するもの**: 絵文字・装飾記号（`☆★♪`）・その他特殊文字

---

## 4. チャンク分割（`splitTextForTTS`）

```javascript
function splitTextForTTS(text, maxLength = 100) {
  const sentences = text.split(/(?<=[。！？])/); // 句読点で分割（句読点は前のチャンクに含める）
  const chunks = [];
  for (const s of sentences) {
    const trimmed = s.trim();
    if (!trimmed) continue;
    if (trimmed.length <= maxLength) {
      chunks.push(trimmed);
    } else {
      // maxLength を超えた文は強制分割
      for (let i = 0; i < trimmed.length; i += maxLength) {
        chunks.push(trimmed.slice(i, i + maxLength));
      }
    }
  }
  return chunks;
}
```

- **分割基準**: `。！？` の後ろで分割（lookbehind により句読点は前チャンクに残る）
- **最大長**: 100文字（Cafe-Lumiere `TTSClient.split_text` と同等）
- **超過時**: 強制的に maxLength 文字ずつスライス

---

## 5. 呼び出し元

`cleanForTTS` + `splitTextForTTS` は以下の3箇所から呼ばれる。

| 呼び出し元 | 用途 |
|---|---|
| `playTTSWithLipSync(text, animCodes)` | チャット返答の TTS 再生 |
| `sendMessage()` 内 `ttsChunks` | アニメ LLM へのチャンク渡し（表情コード生成用） |
| `speakMonologue()` | アイドル独り言の TTS 再生 |

`addMailToChat()` から追加したメールはチャット欄に表示するが、**TTS は呼ばない**（`addMsg` のみ）。

---

## 6. 状態変数まとめ

```javascript
const TTS_AUTO_DICT_KEY  = 'hiyori_tts_auto_dict'; // localStorage キー
let   TTS_DICT           = null;   // 手動辞書（起動時 fetch）
let   TTS_AUTO_DICT      = {};     // 自動かな辞書キャッシュ
const ttsPendingWords    = new Set(); // LLM問い合わせ中の単語
```

---

## 7. 初期化フロー

```
ページロード
  → loadTTSDict()      // tts_dict.yaml を fetch して TTS_DICT にセット
  → loadTTSAutoDict()  // localStorage から TTS_AUTO_DICT を復元
```
