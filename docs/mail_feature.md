# メール機能 実装方針

このドキュメントは `live2d_chat.html` に実装された「AIからユーザーへのメール」機能の設計・実装方針をまとめたものです。

---

## 概要

ユーザーがアプリを閉じている間もAIは「存在し続けている」という演出として、一定時間経過後にメールを1通生成してインボックスに届ける。次回起動時またはアイドル中に生成し、受信ボックスモーダルで表示する。メールはTTSで読み上げない。

---

## 生成トリガー条件

以下の**すべて**を満たすときにメールを生成する。

```
1. 前回の会話から MAIL_IDLE_HOURS 時間以上経過している
2. 未読メールが存在しない（既読消化を促す設計）
3. chatHistory に1件以上の履歴がある（初回起動・会話未開始は生成しない）
```

### チェックタイミング

| タイミング | 詳細 |
|---|---|
| 起動時 | `initMailInbox()` → 3秒後に `generateMail()` を遅延実行（モデル読み込み完了待ち） |
| アイドル中 | `resetMailIdleTimer()` が `MAIL_IDLE_HOURS × 60 × 60 × 1000ms` のタイマーをセット |

### アイドルタイマーのリセット

以下の操作で `resetMailIdleTimer()` を呼ぶ。

- `sendMessage()`（ユーザーがメッセージ送信）
- `speakMonologue()`（独り言発話）

### 最終会話時刻の更新

`updateLastConvoTime()` を `sendMessage()` と `speakMonologue()` の両方から呼び、`localStorage` に保存する。

```javascript
localStorage.setItem('hiyori_last_convo_time', Date.now().toString());
```

---

## .env 設定

```
MAIL_IDLE_HOURS=8    # デフォルト: 8時間
```

`chat_start.ps1` が `%%MAIL_IDLE_HOURS%%` プレースホルダーに注入。ファイルから直接開く場合（プレースホルダー未置換）はデフォルト値 8 にフォールバックする。

```javascript
const _MAIL_IDLE_RAW      = '%%MAIL_IDLE_HOURS%%';
const MAIL_IDLE_HOURS_CFG = (_MAIL_IDLE_RAW.startsWith('%%')) ? 8 : (parseInt(_MAIL_IDLE_RAW) || 8);
const MAIL_IDLE_HOURS     = MAIL_IDLE_HOURS_CFG;
```

---

## メール生成（`generateMail`）

### LLMに渡すコンテキスト

| 情報 | 取得方法 |
|---|---|
| 経過時間 | `Date.now() - lastConvoTime` を日・時間に変換（例:「3日4時間」） |
| 直近の会話 | `chatHistory.slice(-8)` の最後8メッセージ |
| メモリ | `_getAllMemories()` の上位5件（`title: content` 形式） |
| モノローグテーマ | `monologueThemes.slice(0, 3)` |

### プロンプト設計

```
ユーザーとの最後の会話から{経過時間}が経ちました。
その間もひよりはずっと存在し続け、ユーザーのことを思っていました。
ユーザーが次にアプリを開いたときに届くメール（手紙）を1通書いてください。

【ルール】
・本文は最大100文字以内（短くてもよい。20〜30文字でもOK）
・ひよりらしい自然な話し言葉
・「{経過時間}ぶり」など時間経過を自然に織り込む
・前回の会話・思い出・興味のあることのどれかを話題にする
・絵文字・記号不使用
・挨拶不要、本文のみ出力
```

- **temperature**: 0.8
- **maxOutputTokens**: 200

### 100文字オーバー時の処理

```javascript
if (body.length > 100) {
  const cutPoint = body.slice(0, 100).search(/[。！？](?!.*[。！？])/);
  body = cutPoint > 0 ? body.slice(0, cutPoint + 1) : body.slice(0, 100);
}
```

句読点の切れ目でカット。句読点がなければ強制100文字スライス。

---

## ストレージ

| 項目 | 値 |
|---|---|
| ストレージ | `localStorage` |
| キー | `hiyori_mail_inbox` |
| 上限 | 50件（超えたら古いものから削除） |
| 最終会話時刻キー | `hiyori_last_convo_time` |

### メールエントリのスキーマ

```json
{
  "id": "mail_1718000000000",
  "createdAt": 1718000000000,
  "elapsedText": "3日4時間",
  "read": false,
  "addedToChat": false,
  "body": "メール本文（最大100文字）"
}
```

---

## 受信ボックスUI

### エントリポイント

ヘッダー左端の `📪` / `📫` ボタン。

| 状態 | アイコン |
|---|---|
| 未読なし | `📪` |
| 未読あり | `📫`（赤いバッジに件数も表示） |

### モーダルナビゲーション

```
[×] モーダルを閉じる
│
├── 受信ボックス一覧（新しい順、未読は左ボーダー＋ドット表示）
│     └── クリック → メール詳細へ
│
└── メール詳細
      ├── [← 受信ボックスに戻る]
      ├── 日時・経過時間
      ├── 本文
      └── [チャットに追加]（追加済みはdisabled）
```

「チャットに追加」を押してもモーダルは閉じない。

### 既読処理

メール詳細を開いた時点で `read: true` にセットし `updateMailBadge()` を呼ぶ。

---

## 「チャットに追加」の動作

```javascript
function addMailToChat(mailId) {
  // chatHistory に model メッセージとして追加
  chatHistory.push({ role: 'model', parts: [{ text: mail.body }] });
  saveHistory();
  // チャット欄に表示（TTS は呼ばない）
  addMsg('ai', mail.body);
  // フラグ更新
  mail.addedToChat = true;
  saveMailInbox();
}
```

- TTS は**呼ばない**（`playTTSWithLipSync` 不使用）
- `chatHistory` に `role: 'model'` として追加されるため、以降のLLM呼び出しで文脈として参照される

---

## 状態変数

```javascript
const MAIL_INBOX_KEY      = 'hiyori_mail_inbox';
const MAIL_LAST_CONVO_KEY = 'hiyori_last_convo_time';
const MAIL_IDLE_HOURS     = MAIL_IDLE_HOURS_CFG;  // .env から注入
const MAIL_INBOX_MAX      = 50;
let   mailInbox           = [];
let   mailIdleTimer       = null;
let   isGeneratingMail    = false;
```

---

## 初期化フロー

```
ページロード
  → initMailInbox()
      → loadMailInbox()       // localStorage からインボックス復元
      → updateMailBadge()     // アイコン・バッジ更新
      → shouldGenerateMail()  // 条件チェック
          → true なら 3秒後に generateMail()
      → resetMailIdleTimer()  // アイドルタイマー開始
```
