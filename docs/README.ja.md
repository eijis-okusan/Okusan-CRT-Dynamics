# Okusan CRT Dynamics（日本語解説）

[English README](../README.md) | [技術アーキテクチャ詳細 (English)](ARCHITECTURE.md)

**Okusan CRT Dynamics** は、家庭用ブラウン管テレビの**動的な管面挙動（高圧回路の垂れ・525本 480i フィールド交替・P22系蛍光体の残光）**を軽量な2パスで再現する RetroArch 用 CRT シェーダパックです。クリーンな **`okusan-crt-rgb`** と、NTSC RF 変調・雑音・直交復調を再現する **`okusan-crt-rf`** の2種類を収録しています。

同一フォルダ内に **Slang**（`.slangp` / `.slang`、ネイティブ **HDR10** プリセット含む）と **GLSL**（`.glslp` / `.glsl`）の両方を含みます。

### `okusan-crt-rgb`（RGB 接続）

![Okusan CRT Dynamics RGB の RetroArch 表示例](preview.jpg)

### `okusan-crt-rf`（接触甘めの RF テレビ接続）

![Okusan CRT Dynamics RF の RetroArch 表示例](preview-rf.jpg)

---

## 主な特徴

1. **高圧（フライバック）ブルームの再現**
   - Pass 0 が毎フレーム画面の 8×8（64点）グリッドから2乗輝度をサンプリングし、1フレーム前と重み付け平均（`0.58`）した負荷を計算します。
   - フラッシュや全体的に明るい場面でビーム負荷がしきい値（`0.14`）を超えている間、高圧の垂れに合わせてラスタがわずかに外へ膨張し、ガラスハレーションも持ち上がります。
2. **NTSC 525本・480i インターレース描画（240p 切替可）**
   - `OKUSAN_INTERLACED = 1.0` では `FrameCount % 2` に応じて偶奇フィールドを交互走査しつつ、輝度に応じたビーム太さ変調と反対フィールド側の走査線残光近似（`0.55`）を加えます。
   - `0.0` にするとクラシックな 240p プログレッシブ走査線へ切り替わります。
3. **クリアな RGB 電子銃と P22 残光・ガラスハレーション（`okusan-crt-rgb`）**
   - R/G/B 3電子銃のわずかなコンバージェンスずれ（`-0.13 / 0.0 / +0.16`）を伴う水平5タップビームに、1フレーム前との比較による P22 系の短い緑/シアン寄り残光、4近傍ガラス散乱ハレーション、曲面ベゼルリップを組み合わせています。
4. **解像度適応の千鳥 RGB スロットマスク**
   - 出力描画幅に応じてスロットピッチ（`3.0〜6.0px`）とマスク強度を自動調整し、HiDPI 環境でも通常ウィンドウでも細やかで自然なブラウン管の粒感を出します。
5. **NTSC RF 変調・雑音・直交復調エミュレーション（`okusan-crt-rf`）**
   - `okusan-crt-rgb` は一切変更せず別パス（`okusan-crt-rf-display`）として分離しています。
   - 各走査線を YIQ + 3.58 MHz サブキャリア（`2π/3` rad/texel）へ変調し、同軸反射エコー（`-5` / `-10` px）・弱電界フェード・三角関数不使用の 1D 帯域熱雑音＆検波インパルスを波形へ直接乗せた上、1周期6点の直交復調を行うことで、白黒＋ほのかな色砂を帯びた砂嵐・白ドットや細文字へのクロスカラー・ドットクロール・同期の微揺れを物理モデルどおりに同時生成します。
6. **ネイティブ HDR10 物理 CRT 輝度強調 & ABL（`*-hdr.slangp`）**
   - `A2B10G10R10_UNORM_PACK32`（Rec.2020 + ST.2084 PQ）形式で直接出力する HDR10 専用 Slang プリセットを追加しています。
   - 黒や暗部・ベゼルの階調は SDR 基準を保ったまま、走査線やスロットマスクで失われる輝度を補償し、Pass 0 のビーム負荷に応じた物理 ABL（通常〜中負荷は高ピーク発光、全画面フラッシュ時は穏やかに垂れ）とソフトリミッタでブラウン管らしい力強いハイライトを再現します。

---

## プリセット

| プリセット | 形式 | 対応映像ドライバ | 内容 |
| --- | --- | --- | --- |
| `okusan-crt-rgb.slangp` | Slang | Metal (Mac標準), Vulkan, D3D11/12 | クリーンな RGB ブラウン管（SDR） |
| `okusan-crt-rf.slangp` | Slang | Metal (Mac標準), Vulkan, D3D11/12 | NTSC RF 変調・砂嵐・偽色テレビ（SDR） |
| `okusan-crt-rgb-hdr.slangp` | Slang (HDR10) | Vulkan, D3D11/12 (HDR ON) | ネイティブ HDR10 対応 RGB ブラウン管（物理 ABL 搭載） |
| `okusan-crt-rf-hdr.slangp` | Slang (HDR10) | Vulkan, D3D11/12 (HDR ON) | ネイティブ HDR10 対応 NTSC RF テレビ（物理 ABL 搭載） |
| `okusan-crt-rgb.glslp` | GLSL | OpenGL (`gl` / `glcore`) | クリーンな RGB ブラウン管（SDR） |
| `okusan-crt-rf.glslp` | GLSL | OpenGL (`gl` / `glcore`) | NTSC RF 変調・砂嵐・偽色テレビ（SDR） |

---

## RetroArch への導入手順

1. `Okusan-CRT-Dynamics` フォルダを RetroArch のシェーダフォルダへコピーします（**設定 → ディレクトリ → ビデオシェーダ** 配下の `shaders_slang/` または `shaders_glsl/`、あるいは `shaders/` 直下）。
2. *（HDR10 プリセットを使う場合）* HDR 対応ディスプレイ＋対応ドライバ（Vulkan / D3D11 / D3D12）環境で、あらかじめ **設定 → ビデオ → HDR → HDR を有効にする** を **ON** にしておきます（SDR 環境や macOS の非 HDR スワップチェーン環境では通常の `.slangp` をお使いください）。
3. ゲームを何か1本起動し、**クイックメニュー**（`F1` / Mac では `fn + F1`）を開きます。
4. **シェーダ → ビデオシェーダ** を **ON** にします。
5. **読み込む (`Load Preset`) → `Okusan-CRT-Dynamics`** から **`okusan-crt-rgb`**、**`okusan-crt-rf`**、**`okusan-crt-rgb-hdr`**、または **`okusan-crt-rf-hdr`** を選択します。
6. 毎回自動で適用したい場合は **シェーダ → 保存 → グローバルプリセットを保存** を実行します。

---

## パラメータ一覧

| パラメータ名 | 対象 | 初期値 | 範囲 | 調整内容 |
| --- | --- | --- | --- | --- |
| `OKUSAN_INTERLACED` | 共通 | `1.0` | `0.0 - 1.0` | `1.0`: 525本 480i 交互走査 / `0.0`: 240p 走査線 |
| `OKUSAN_HV_BLOOM` | 共通 | `1.0` | `0.0 - 2.0` | 全画面フラッシュ時の高圧垂れ膨張とハレーション増加量 |
| `OKUSAN_CURVATURE` | 共通 | `1.0` | `0.0 - 1.5` | ブラウン管の管面カーブの強さ（`0.0` でフラット） |
| `OKUSAN_MASK_STRENGTH` | 共通 | `1.0` | `0.0 - 1.5` | RGB スロットマスクの濃さ |
| `OKUSAN_RF_SNOW` | RF / RF-HDR | `1.0` | `0.0 - 2.0` | RF 雑音波形の強さ・黒浮き・同期微揺れ（`0.0` でノイズ無し） |
| `OKUSAN_RF_SIGNAL` | RF / RF-HDR | `1.0` | `0.0 - 2.0` | 弱電界フェード・同軸反射ゴースト・3.58 MHz 偽色の強さ |
| `OKUSAN_HDR_PAPER_WHITE` | `*-hdr` | `250.0` | `80.0 - 600.0` | SDR 白基準（Paper White）の輝度（nits） |
| `OKUSAN_HDR_MAX_NITS` | `*-hdr` | `800.0` | `200.0 - 4000.0` | ディスプレイの最大ピーク輝度上限（nits） |
| `OKUSAN_HDR_BOOST` | `*-hdr` | `1.0` | `0.0 - 1.5` | 物理 ABL ピーク強調倍率（`0.0` で SDR 同等の基準輝度） |
| `OKUSAN_HDR_EXPAND_GAMUT` | `*-hdr` | `0.0` | `0.0 - 1.0` | `0.0`: 忠実な Rec.709 ブラウン管色域 / `1.0`: 拡張色域 |

---

## 注意事項（初回読み込み時）

- 初めてプリセットを読み込んだ直後（特に Mac の Metal や Vulkan で `.slangp` を使う場合）、RetroArch 側でシェーダのコンパイルとキャッシュ生成が走るため、一時的に音声へノイズ・音割れや一瞬の引っかかりが出ることがあります。
- キャッシュ作成後（2回目以降の起動時）は落ち着いて動作します。万一継続的に音割れが出る場合は、**設定 → オーディオ → 出力 → オーディオレイテンシ (ms)** を `96〜128` 程度に増やしてみてください。

---

## ライセンス

[MIT License](../LICENSE) のもとで公開しています。
