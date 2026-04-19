# TTS API 実装方針

このドキュメントは `live2d_chat.html` に実装された TTS API 呼び出し・音声再生・リップシンクの設計・実装方針をまとめたものです。
新規コード生成時の参考資料として使用してください。

---

## 対応プロバイダ

| プロバイダ | 識別子 | デフォルトエンドポイント |
|---|---|---|
| Style-Bert-VITS2 | `sbv2` | `http://localhost:5000` |
| VOICEVOX | `voicevox` | `http://localhost:50021` |

プロバイダは `.env` の `TTS_PROVIDER` で選択し、`chat_start.ps1` が `%%TTS_PROVIDER%%` プレースホルダーに注入する。

---

## 設定変数

すべて `chat_start.ps1` が `.env` から注入するプレースホルダー。

```javascript
const TTS_PROVIDER   = '%%TTS_PROVIDER%%';   // 'sbv2' | 'voicevox'
const TTS_ENDPOINT   = '%%TTS_ENDPOINT%%';   // サーバーURL
const TTS_MODEL      = '%%TTS_MODEL%%';       // SBV2: モデル名（例: woman001）
const TTS_SPEAKER_ID = %%TTS_SPEAKER_ID%%;   // VOICEVOX: スピーカーID（例: 3）
const TTS_VOLUME     = %%TTS_VOLUME%%;        // 音量 0.0〜1.0（Web Audio GainNode に適用）
```

ランタイム変数:

```javascript
let ttsEnabled = true;   // ON/OFF（設定パネルのトグルボタンで切替）
let ttsSpeed   = 1.0;    // 話速（UIスライダー 0.6〜1.5、ステップ 0.1）
```

### .env 設定項目

```
TTS_PROVIDER=sbv2
TTS_ENDPOINT=http://localhost:5000
TTS_MODEL=woman001
TTS_SPEAKER_ID=3
TTS_VOLUME=1.0
```

---

## API 呼び出し

### Style-Bert-VITS2（sbv2）

1リクエストで音声バイナリを取得。

```
GET /voice?text={text}&model_name={TTS_MODEL}&length={ttsSpeed}&style_weight=1.0&split_interval=0.3
```

| パラメータ | 値 | 説明 |
|---|---|---|
| `text` | チャンクテキスト | 前処理済みテキスト |
| `model_name` | `TTS_MODEL` | 音声モデル名 |
| `length` | `ttsSpeed` | 話速スケール（1.0=標準、大きいほど遅い） |
| `style_weight` | `1.0` | スタイル強度（固定） |
| `split_interval` | `0.3` | 文内ポーズ秒数（固定） |

レスポンス: 音声バイナリ（`arrayBuffer()`）

### VOICEVOX

2ステップAPI。

**Step 1: audio_query**

```
POST /audio_query?text={text}&speaker={TTS_SPEAKER_ID}
```

レスポンス: クエリJSONオブジェクト

**Step 2: synthesis**

```javascript
query.speedScale = ttsSpeed; // クエリに話速を上書きしてから送信

POST /synthesis?speaker={TTS_SPEAKER_ID}
Content-Type: application/json
Body: {クエリJSON}
```

レスポンス: 音声バイナリ（`arrayBuffer()`）

### CORS 設定

両サーバーともローカル起動時に CORS 許可が必要。

```bash
# Style-Bert-VITS2
python server_fastapi.py --allow-origins='*'

# VOICEVOX
# アプリ設定 → 「他のアプリからのエンジンAPIを許可する」をON
```

---

## 音声再生（Web Audio API）

### AudioContext 管理

```javascript
let audioCtx = null;

function getAudioCtx() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  if (audioCtx.state === 'suspended') audioCtx.resume();
  return audioCtx;
}
```

**モバイル対応**: iOS/Android は AudioContext をユーザーのジェスチャー内で `resume()` する必要がある。`touchstart` と `click` イベントで `_unlockAudioCtx()` を登録し、最初のタップ時に確実にアンロックする。

```javascript
document.addEventListener('touchstart', _unlockAudioCtx, { passive: true });
document.addEventListener('click',      _unlockAudioCtx, { passive: true });
```

### ノードグラフ

```
BufferSource → AnalyserNode → GainNode → destination
                   │
                   └── RMS振幅 → ParamMouthOpenY（リップシンク）
```

### 音量（GainNode）

```javascript
gainNode.gain.value = TTS_VOLUME; // .env の TTS_VOLUME を適用（0.0〜1.0）
```

### リップシンク

`AnalyserNode` から取得した RMS振幅を `ParamMouthOpenY` に変換してLive2Dモデルを動かす。

```javascript
analyser.fftSize               = 512;
analyser.smoothingTimeConstant = 0.5;

// フレームごとの更新（requestAnimationFrame）
analyser.getFloatTimeDomainData(dataArray);
let rms = 0;
for (let v of dataArray) rms += v * v;
rms = Math.sqrt(rms / dataArray.length);
const target = Math.min(1.0, rms * 7.0);
// スムージング（急激な変化を抑制）
currentMouthVal = currentMouthVal * 0.55 + target * 0.45;
setParamDirect('ParamMouthOpenY', currentMouthVal);
```

---

## チャンク順次再生とキャンセル

### キャンセルID方式

```javascript
let ttsCancelId    = 0;
let currentSource  = null; // 再生中の BufferSource
```

新しい `playTTSWithLipSync()` 呼び出し時にインクリメントし、古い再生ループを自然に終了させる。

```javascript
ttsCancelId++;
const myId = ttsCancelId;
// 各チャンク処理時に確認
if (myId !== ttsCancelId || !ttsEnabled) break;
```

### 再生フロー

```javascript
async function playTTSWithLipSync(text, animCodes = []) {
  if (!ttsEnabled) return;
  ttsCancelId++;          // 進行中の再生をキャンセル
  const myId = ttsCancelId;
  if (currentSource) { currentSource.stop(); currentSource = null; }

  const chunks = splitTextForTTS(cleanForTTS(text));

  isSpeaking = true;
  for (let i = 0; i < chunks.length; i++) {
    if (myId !== ttsCancelId || !ttsEnabled) break;
    if (animCodes[i]) applyAnimCode(animCodes[i]); // チャンクに対応する表情コードを適用
    await playTTSChunk(chunks[i], myId);
  }
  isSpeaking = false;
}
```

---

## アニメーション連携（表情コード）

チャット返答時、`animEnabled` が ON の場合はアニメ LLM を呼び出して各チャンクの表情コードを取得してから TTS を再生する。

```javascript
// sendMessage() 内
const ttsChunks = splitTextForTTS(cleanForTTS(aiText));

if (animEnabled) {
  callLLMAnimChunks(text, aiText, ttsChunks)
    .then(animCodes => playTTSWithLipSync(aiText, animCodes))
    .catch(() => playTTSWithLipSync(aiText, []));
} else {
  playTTSWithLipSync(aiText, []);
}
```

独り言（`speakMonologue`）でも同様に `animEnabled` で分岐する。

---

## 状態変数まとめ

```javascript
let ttsEnabled      = true;    // ON/OFFフラグ
let ttsSpeed        = 1.0;     // 話速（UIスライダーで変更）
let isSpeaking      = false;   // 再生中フラグ（他の処理で参照）
let ttsCancelId     = 0;       // キャンセルID（インクリメントで古い再生を停止）
let currentSource   = null;    // 再生中の AudioBufferSourceNode
let currentMouthVal = 0;       // 現在の口の開き量（スムージング用）
let audioCtx        = null;    // Web Audio AudioContext（遅延初期化）
```

---

## エラーハンドリング

- TTS API がエラーを返した場合: `console.warn` でログを出力し、**口を閉じてチャンクをスキップ**（クラッシュしない）
- チャンク中断時（`cancelId` 不一致）: `return` で早期終了
- `ttsEnabled` が OFF の場合: `playTTSWithLipSync` の先頭で即 `return`

---

## TTS を呼ばない箇所

以下は意図的に TTS を呼ばない。

| 処理 | 理由 |
|---|---|
| メールの「チャットに追加」| 手紙をアバターが音読するのは不自然 |
| `addMsg('sys', ...)` | システム通知メッセージ |
| チャット履歴のインポート・復元 | 大量テキストを再生しない |
