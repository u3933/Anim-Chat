# 表情・アニメーション制御 実装方針

このドキュメントは、LLMがTTSチャンクに対応した表情コードを生成し、アバターの表情を動的に制御する仕組みの設計・実装方針をまとめたものです。

現在の実装は **Live2D** ですが、設計思想は静止画（表情画像切替）・VRMモデルへの転用を考慮して記載しています。

---

## 概念設計

```
LLM返答テキスト
    │
    ▼
splitTextForTTS() でチャンク分割
    │ chunks = ["こんにちは！", "今日もいい天気だね。", "何か話そうか？"]
    ▼
callLLMAnimChunks(userMessage, aiResponse, chunks)
    │ → LLM が各チャンクに対応する「表情コード」を生成
    │ → animCodes = ["happy_code", "thinking_code", "excited_code"]
    ▼
playTTSWithLipSync(text, animCodes)
    │ チャンクを順次TTS再生しながら、対応する表情コードを適用
    └─ applyAnimCode(animCodes[i]) ← チャンク再生前に呼ぶ
```

---

## LLMへのプロンプト設計

### 入力

```
You control [アバター名]'s facial expressions as she speaks.
She speaks these text segments one by one (TTS chunks):
[0] "こんにちは！"
[1] "今日もいい天気だね。"
[2] "何か話そうか？"

Context — User said: "{userMessage}"
Context — [アバター名]'s full response: "{aiResponse}"

For each segment, assign one expression code snippet.
```

### 出力形式（厳守）

```json
[
  {"i": 0, "code": "..."},
  {"i": 1, "code": "..."},
  {"i": 2, "code": "..."}
]
```

- JSON配列のみ出力（Markdownコードブロック・説明文なし）
- インデックス `i` はチャンク番号に対応
- 欠落したインデックスは `null`（スキップ）として扱う

### 生成パラメータ

| 項目 | 値 |
|---|---|
| temperature | 0.4（安定したJSON出力のため低め） |
| maxOutputTokens | 1200 |

### レスポンスのパース

```javascript
function parseAnimResponse(rawText, chunkCount) {
  const raw = (rawText || '')
    .replace(/```[\w]*\n?/g, '')
    .replace(/```/g, '')
    .trim();
  const parsed = JSON.parse(raw);
  const result = new Array(chunkCount).fill(null);
  for (const item of parsed) {
    if (typeof item.i === 'number' && item.i < chunkCount && item.code) {
      result[item.i] = item.code;
    }
  }
  return result;
}
```

---

## アバター別の実装方針

### Live2D（現行実装）

#### パラメータ仕様（PARAM_SPEC）

プロンプトにパラメータ仕様を含め、LLMが正しい関数・値域を使えるようにする。

```
=== LIVE2D PARAMETER SPEC ===
FACE: ParamAngleX/Y/Z(-100~100), ParamCheek(-1~1,blush)
EYES: ParamEyeLOpen/ROpen(0~1.2), ParamEyeLSmile/RSmile(0~1), ParamEyeBallX/Y(-1~1)
BROWS: ParamBrowLY/RY(-1~1), ParamBrowLAngle/RAngle(-1~1), ParamBrowLForm/RForm(-1~1)
MOUTH: ParamMouthForm(-2~1,1=smile,0=neutral,-2=frown), ParamMouthOpenY ※lip-sync専用
BODY: ParamBodyAngleX(-10~10), ParamShoulder(-1~1)
ARMS: ParamArmLB/RB(-100~100), ParamHandLB/RB(-10~10), ParamHandL/R(-1~1,1=open)
FORBIDDEN: ParamBreath, ParamBodyAngleZ, ParamBodyAngleY（自律ループが制御）
```

#### 表情コードの制約

```
1. 先頭に必ず前回アニメのキャンセル処理を入れる:
   if(window.__animId){cancelAnimationFrame(window.__animId);window.__animId=null;}

2. ParamMouthOpenY はリップシンクが制御するため設定禁止

3. 最終チャンク以外: static な setParam() のみ使用（ループなし）

4. 最終チャンクのみ: requestAnimationFrame ループを許可
   （手を振る・興奮するなど感情が大きい場合）

5. 連続するチャンクで表情を自然に変化させる（単調にしない）
```

#### 基本表情スニペット（プロンプトの参考例として提示）

```javascript
// happy
setParam('ParamEyeLSmile',1);setParam('ParamEyeRSmile',1);
setParam('ParamMouthForm',1);setParam('ParamBrowLY',0.5);setParam('ParamBrowRY',0.5);setParam('ParamCheek',0.5);

// thinking
setParam('ParamAngleZ',10);setParam('ParamEyeBallY',0.3);
setParam('ParamBrowLY',0.3);setParam('ParamBrowRY',0.3);setParam('ParamMouthForm',0.5);

// sad
setParam('ParamMouthForm',-2);setParam('ParamBrowLY',-1);setParam('ParamBrowRY',-1);
setParam('ParamBrowLForm',-1);setParam('ParamBrowRForm',-1);
setParam('ParamEyeLOpen',0.6);setParam('ParamEyeROpen',0.6);

// surprised
setParam('ParamEyeLOpen',1.2);setParam('ParamEyeROpen',1.2);
setParam('ParamBrowLY',1);setParam('ParamBrowRY',1);setParam('ParamMouthForm',0);

// shy
setParam('ParamCheek',1);setParam('ParamAngleY',-15);setParam('ParamAngleZ',5);
setParam('ParamEyeLSmile',0.5);setParam('ParamEyeRSmile',0.5);

// excited（最終チャンクのみ・ループ）
let t=0;function f(){t+=0.12;
  setParam('ParamArmRB',Math.sin(t)*10);setParam('ParamHandR',1);
  setParam('ParamEyeLSmile',0.8);setParam('ParamEyeRSmile',0.8);setParam('ParamMouthForm',1);
  window.__animId=requestAnimationFrame(f);}
window.__animId=requestAnimationFrame(f);
```

#### コード実行（`applyAnimCode`）

```javascript
function applyAnimCode(code) {
  if (!code) return;
  try {
    if (window.__animId) { cancelAnimationFrame(window.__animId); window.__animId = null; }
    new Function(code)(); // eval の代替（スコープ分離）
  } catch(e) {
    console.warn('[Anim] Exec error:', e.message);
  }
}
```

`new Function(code)()` でサンドボックスに近い形で実行。エラーは `warn` でスキップ（クラッシュしない）。

#### setParam の二重実装

```javascript
// LLMコード用（フラグ更新あり・アイトラッキング等の自律挙動を一時停止する場合）
function setParam(id, value) { ... }

// 内部処理用（シンプルなラッパー）
function setParamDirect(id, value) {
  live2dModel.internalModel.coreModel.setParameterValueById(id, value, 1.0);
}
```

---

### 静止画（表情画像切替）への転用

Live2DのパラメータAPIの代わりに、表情名に対応した画像ファイルを切り替える方式。

#### LLMへのプロンプト変更点

PARAM_SPECを画像ファイル一覧の仕様に差し替える。

```
=== EXPRESSION SPEC ===
Available expressions: "normal", "happy", "thinking", "sad", "surprised", "shy", "excited"
```

#### 出力形式の変更

コード文字列の代わりに表情名のみを返させる。

```json
[
  {"i": 0, "expression": "happy"},
  {"i": 1, "expression": "thinking"},
  {"i": 2, "expression": "excited"}
]
```

#### 適用関数の実装例

```javascript
function applyAnimCode(expressionName) {
  if (!expressionName) return;
  const imgEl = document.getElementById('avatar-image');
  imgEl.src = `expressions/${expressionName}.png`;
}
```

画像ファイルは `expressions/` フォルダに `happy.png`, `thinking.png` などを配置。

---

### VRMモデルへの転用

Three.js + @pixiv/three-vrm を使用する場合の参考設計。

#### LLMへのプロンプト変更点

PARAM_SPECをVRMのBlendShape（表情）仕様に差し替える。

```
=== VRM EXPRESSION SPEC ===
Use vrm.expressionManager.setValue(name, weight):
  "happy"(0~1), "angry"(0~1), "sad"(0~1), "surprised"(0~1), "relaxed"(0~1)
Use vrm.humanoid.getNormalizedBoneNode(boneName).rotation for head/body:
  "head": .x(nod), .y(turn), .z(tilt)
Call vrm.expressionManager.update() after setting values.
```

#### 適用関数の実装例

```javascript
function applyAnimCode(code) {
  if (!code || !vrm) return;
  const setParam = (name, value) => {
    vrm.expressionManager.setValue(name, value);
    vrm.expressionManager.update();
  };
  try {
    new Function('vrm', 'setParam', code)(vrm, setParam);
  } catch(e) {
    console.warn('[Anim] VRM exec error:', e.message);
  }
}
```

---

## アニメON/OFFの分岐

`animEnabled` フラグで制御。OFFの場合はLLMへのアニメコード生成リクエストをスキップし、表情変化なしで即TTS再生する。

```javascript
if (animEnabled) {
  callLLMAnimChunks(userMessage, aiText, ttsChunks)
    .then(animCodes => playTTSWithLipSync(aiText, animCodes))
    .catch(() => playTTSWithLipSync(aiText, []));
} else {
  playTTSWithLipSync(aiText, []);
}
```

アニメLLMのエラー時も `.catch(() => playTTSWithLipSync(aiText, []))` で表情なし再生にフォールバックする（TTS自体は必ず再生される）。

---

## 独り言での利用

独り言（`speakMonologue`）でも同じ `callLLMAnimChunks` を使用。ユーザーメッセージは空文字を渡す。

```javascript
callLLMAnimChunks('', line, chunks)
  .then(codes => playTTSWithLipSync(line, codes))
  .catch(() => playTTSWithLipSync(line, []));
```

---

## 状態変数

```javascript
let animEnabled    = true;          // アニメON/OFFフラグ
let window.__animId = null;         // requestAnimationFrame ID（グローバル・キャンセル用）
```
