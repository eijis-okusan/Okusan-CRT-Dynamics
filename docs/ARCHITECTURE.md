# Architecture & Signal Model

This document describes how **Okusan CRT Dynamics** splits temporal beam-current estimation and final CRT phosphor synthesis across its two shader passes, covering both the clean RGB pass (`okusan-crt-display`) and the NTSC RF pass (`okusan-crt-rf-display`).

## Pass 0 — Beam Load Estimator (`okusan-crt-beamload`)

Rendered into a `32x32` floating-point framebuffer (`float_framebuffer0 = "true"`), Pass 0 estimates whole-screen beam current so Pass 1 can react to high-voltage sag without scanning dozens of pixels per viewport fragment.

1. **Grid Sampling (`sampleBeamCurrent`)**: Evaluates a uniform `8x8` grid (64 points) across the active picture area of both the current source frame (`OrigTexture` / `Original`) and the immediately preceding source frame (`PrevTexture` / `OriginalHistory1`).
2. **Power Proxy**: Each sample is converted to approximate linear RGB using `pow(max(rgb, 1e-6), SRC_GAMMA)` (`SRC_GAMMA = 2.25`), projected onto Rec.601 luminance (`LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114)`), and **squared** (`luma * luma`) so bright flashes outweigh midtones similarly to actual CRT beam current demand.
3. **Capacitive Damping**: Frame load is averaged and smoothed with an asymmetric RC-style step (`mix(loadPrev, loadNow, HV_CAP_BLEND)`, `HV_CAP_BLEND = 0.58`), writing `(dampedLoad, loadNow, 0.0, 1.0)`.

Because GLSL backends frequently pad source textures to power-of-two dimensions, `sampleBeamCurrent` scales normalized grid UVs by `inputSz / max(texSz, 1.0)` before sampling.

---

## Pass 1A — Interlaced RGB CRT Display (`okusan-crt-display`)

Rendered at full viewport resolution, Pass 1 reconstructs the tube face and electron-beam raster in linear light before final gamma encoding:

### 1. Tube Curvature & Bezel SDF (`roundedBezelDistance`)
- Normalized face coordinates `[-1, 1]` undergo barrel warping (`vec2(0.083, 0.110) * OKUSAN_CURVATURE`) with subtle scale compensation (`1.0 + 0.015 * OKUSAN_CURVATURE`).
- `roundedBezelDistance` evaluates a signed distance box (`vec2(0.924, 0.906)`) with corner radius `0.074`. Pixels outside `edgeDistance > 0.07` return early with shaded bezel glass, while the transition region produces both an interior aperture mask and a specular bezel lip (`exp(-abs(edgeDistance - 0.023) * 75.0)`).

### 2. Flyback HV Bloom (`loadExcess`)
- Reads Pass 0's `dampedLoad` and applies a knee at `BEAM_LOAD_KNEE = 0.14`:
  ```glsl
  float loadExcess = max(beamLoad - BEAM_LOAD_KNEE, 0.0) * OKUSAN_HV_BLOOM;
  float hvBloom = 1.0 + HV_SAG_EXPANSION * loadExcess; // HV_SAG_EXPANSION = 0.015
  ```
- Dividing curved screen coordinates by `vec2(0.94, 0.90) * hvBloom` expands the active raster outward under heavy screen load, reproducing anode voltage sag on consumer flyback transformers.

### 3. Horizontal RGB Electron Beam & Convergence (`sampleHorizontalBeam`)
- `sampleHorizontalBeam` filters 5 horizontal source texels (`i = -2..2`) using a crisp Gaussian beam profile (`BEAM_SIGMA_X = 0.55` texels).
- Subtle per-gun convergence offsets (`GUN_CONVERGENCE = vec3(-0.13, 0.0, 0.16)` texels for R, G, B) add realistic analog gun misalignment along sharp vertical transitions without softening flat fills.

### 4. Scanline Synthesis (`synthesizeScanlines`)
- **Interlaced mode (`OKUSAN_INTERLACED > 0.5`)**:
  - Maps the vertical raster span onto `NTSC_VISIBLE_LINES = 480.0` visible lines (525 total lines minus 45 vertical blanking lines).
  - `fieldParity = mod(float(FrameCount), 2.0)` switches active lines between even and odd fields every frame.
  - Beam width expands mildly with local peak luminance and `loadExcess` (`0.48 + 0.12 * sqrt(peakLum) + 0.03 * loadExcess`), blending the current field with `0.55 * residualLight` from the alternate field and tapering smoothly via `dFdy(tvLine)` when output scale is small.
- **Progressive mode (`OKUSAN_INTERLACED <= 0.5`)**:
  - Models crisp 240p scanlines across adjacent source rows with brightness-dependent beam spot widths (`mix(0.24, 0.42, sqrt(maxChannel))`).

### 5. P22 Persistence & Glass Halation (`applyGlassHalation`)
- **Phosphor Decay**:
  - Compares `PrevTexture` / `OriginalHistory1` against the current un-interlaced sample and adds falling-edge persistence biased toward P22 green/cyan phosphors (`P22_DECAY = vec3(0.055, 0.11, 0.075)`).
- **Glass Scatter Halation**:
  - Samples 4 axial neighbors `(±2.6, 0)` and `(0, ±1.65)` in squared linear intensity, scaled by `0.044 + 0.036 * loadExcess` so bright scenes also lift internal glass scatter.

### 6. Viewport-Scaled Slot Mask & Output (`applyPhosphorMask`)
- `applyPhosphorMask` computes a physical pixel pitch clamped to `[3.0, 6.0]` screen pixels based on `viewWidth / (srcWidth * 1.35)` (matching fine HiDPI tube slot density while keeping non-HiDPI windows smooth), staggering R/G/B phosphor slots on alternating mask rows with subtle vertical row gaps.
- Mask contrast fades smoothly between `360px` and `750px` viewport widths to keep small windows legible.
- Final light undergoes corner vignetting, light 60 Hz hum (`0.003`), `DISPLAY_INV_GAMMA = 1.0 / 2.2` display gamma encoding, faint tube noise (`0.008`), bezel clipping, and subtle top-left glass reflection.

---

## Pass 1B — Loose NTSC RF CRT Display (`okusan-crt-rf-display`)

`okusan-crt-rf` reuses Pass 0 (`okusan-crt-beamload`) and the scanline/persistence/halation/mask stages identically, replacing the clean 5-tap RGB horizontal sampler with `sampleRfScanline`:

1. **Cable Echoes & AGC Washout**: Adds delayed impedance-mismatch reflections (`RF_GHOST_NEAR_TAP = -5.0` at `+0.12`, `RF_GHOST_FAR_TAP = -10.0` at `-0.04`) and weak-RF contrast/chroma washout in YIQ without rotating base hues.
2. **3.58 MHz Subcarrier Modulation & Waveform Noise (`sampleRfWaveformNoise`)**: Modulates YIQ onto a `2*pi/3` rad/texel subcarrier (`SUBCARRIER_RAD_PER_TEXEL`), then injects 1D scanline-independent noise composed of three summed band-limited 1D waves (`0.85x`, `1.35x`, `1.95x` texel rates) plus IF detector impulse spikes generated by sin-free hashes (`hash13`). Horizontal sync micro-flutter (`RF_SYNC_FLUTTER = 0.30`) slightly perturbs scanline phase.
3. **6-Tap Orthogonal Demodulation**: Integrates across one full subcarrier cycle (`6` taps at `0.5` px = `60°` increments). Flat areas cancel cross-terms cleanly, while sharp white dots/text alias into realistic cross-color, chroma transitions create dot crawl, and RF waveform noise splits into full-bandwidth luma static plus narrower chroma bandpass speckle (`RF_CHROMA_NOISE_PASSBAND = 0.45`).

---

## Modular Slang Includes & Native HDR10 Pipeline (`*-hdr`)

Shared CRT, RF, and HDR10 functions are factored into `shaders/include/` so SDR and HDR passes share identical signal and beam math:

- `shaders/include/okusan-crt-common.inc`: 5-tap horizontal RGB beam, bezel SDF, 480i/240p scanlines, 4-tap glass halation, and viewport-scaled slot mask (with optional `hdrFactor` shadow/peak compensation).
- `shaders/include/okusan-crt-rf.inc`: YIQ modulation/demodulation, echo reflections, 1D band-limited Gaussian + impulse RF noise, and sin-free hashes.
- `shaders/include/okusan-hdr10.inc`: Physical ABL peak regulation, soft knee limiter, Rec.709 / Expanded-709 -> Rec.2020 color matrices, and ST.2084 PQ encoding.

### HDR10 Output (`okusan-crt-display-hdr.slang` / `okusan-crt-rf-display-hdr.slang`)
1. **Direct HDR10 Swapchain Signaling**: Declares `#pragma format A2B10G10R10_UNORM_PACK32` so RetroArch passes the shader's ST.2084 PQ Rec.2020 output directly when **Video → HDR** is enabled.
2. **Physical ABL Peak Boost (`okusanComputeHdrFactor` / `okusanFinalizeHdr10`)**:
   - Computes headroom `clamp(MaxNits / PaperWhiteNits, 1.0, 4.0)` and drives dark/mid scenes with high highlight headroom (`1.0 + 0.92 * hdrFactor`), while heavy Pass 0 `beamLoad` flashes droop smoothly (`1.0 + 0.16 * hdrFactor`) like a real flyback Automatic Beam Limiter.
   - Modulates peak drive cleanly above shadow/midtones (`smoothstep(0.05, 0.60, lum)`) so black levels remain identical to SDR, and rolls highlights cleanly below `MaxNits` via `okusanHdrSoftLimit`.
   - Deepens slot mask shadow valleys (`0.72 -> 0.54`) while boosting phosphor centers (`0.45 -> 0.72`) to compensate for aperture mask light loss.
3. **PQ Encoding**: Transforms calibrated linear light + bezel glass into Rec.2020, scales by `OKUSAN_HDR_PAPER_WHITE / 10000.0`, and encodes via `LinearToST2084`.
