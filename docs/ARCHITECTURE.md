# Architecture & Signal Model

This document describes how **Okusan CRT Dynamics** splits temporal beam-current estimation and final phosphor synthesis across its two shader passes.

## Pass 0 — Beam Load Estimator (`okusan-crt-beamload`)

Rendered into a `32x32` floating-point framebuffer (`float_framebuffer0 = "true"`), Pass 0 estimates whole-screen beam current so Pass 1 can react to high-voltage sag without scanning dozens of pixels at every viewport fragment.

1. **Grid Sampling**: Evaluates a uniform `8x8` grid (64 points) across the active picture area of both the current source frame (`OrigTexture` / `Original`) and the immediately preceding source frame (`PrevTexture` / `OriginalHistory1`).
2. **Power Proxy**: Each sample is converted to approximate linear RGB using `pow(max(rgb, 0.0), 2.25)`, projected onto Rec.601 luminance (`0.299 R + 0.587 G + 0.114 B`), and **squared** (`luma * luma`) so bright flashes outweigh midtones similarly to actual CRT beam current demand.
3. **Capacitive Damping**: Frame load is averaged and smoothed with an asymmetric RC-style step (`mix(loadPrev, loadNow, 0.58)`), writing `(dampedLoad, loadNow, 0.0, 1.0)`.

Because GLSL backends frequently pad source textures to power-of-two dimensions, `sampleBeamCurrent` scales normalized grid UVs by `inputSz / max(texSz, 1.0)` before sampling.

---

## Pass 1 — Interlaced CRT Display (`okusan-crt-display`)

Rendered at full viewport resolution, Pass 1 reconstructs the tube face and electron-beam raster in linear light before final gamma encoding:

### 1. Tube Curvature & Bezel SDF
- Normalized face coordinates `[-1, 1]` undergo barrel warping (`vec2(0.083, 0.110) * OKUSAN_CURVATURE`) with subtle scale compensation.
- `roundedBezelDistance` evaluates a signed distance box (`vec2(0.924, 0.906)`) with corner radius `0.074`. Pixels outside `edgeDistance > 0.07` return early with shaded bezel glass, while the transition region produces both an interior aperture mask and a specular bezel lip (`exp(-abs(edgeDistance - 0.023) * 75.0)`).

### 2. Flyback HV Bloom (`loadExcess`)
- Reads Pass 0's `dampedLoad` and applies a knee at `0.14`:
  ```glsl
  float loadExcess = max(beamLoad - 0.14, 0.0) * OKUSAN_HV_BLOOM;
  float hvBloom = 1.0 + 0.015 * loadExcess;
  ```
- Dividing curved screen coordinates by `vec2(0.94, 0.90) * hvBloom` expands the active raster outward under heavy screen load, reproducing anode voltage sag on consumer flyback transformers.

### 3. Horizontal Electron Beam & Convergence
- `sampleHorizontalBeam` filters 5 horizontal source texels (`i = -2..2`) using a Gaussian profile whose standard deviation widens from `0.55` (RGB) to `0.86` (Composite).
- Subtle per-gun convergence offsets (`vec3(-0.13, 0.0, 0.16)` texels for R, G, B) add realistic analog beam misalignment along high-contrast vertical edges without blurring flat fills.

### 4. Scanline Synthesis (525-Line 480i vs. 240p)
- **Interlaced mode (`OKUSAN_INTERLACED > 0.5`)**:
  - Maps the vertical raster span onto `480.0` visible NTSC lines (corresponding to 525 total lines minus vertical blanking).
  - `fieldParity = mod(float(FrameCount), 2.0)` switches active lines between even and odd fields every frame.
  - Beam width expands mildly with local peak luminance and `loadExcess` (`0.48 + 0.12 * sqrt(peakLum) + 0.03 * loadExcess`), blending the current field with `0.55 * residualLight` from the alternate field and tapering smoothly via `dFdy(tvLine)` when output scale is small.
- **Progressive mode (`OKUSAN_INTERLACED <= 0.5`)**:
  - Models crisp 240p scanlines across adjacent source rows with brightness-dependent beam spot widths (`mix(0.24, 0.42, sqrt(maxChannel))`).

### 5. Composite Bleed, P22 Persistence & Halation
- **Composite & RF Demodulation (`OKUSAN_COMPOSITE > 0.5`, `OKUSAN_RF > 0.0`)**:
  - `applyCompositeBleed` keeps sharp luminance transitions intact while smearing chroma (`spread - luma`) asymmetrically across horizontal taps `(-3, -1, +2)` with weight `0.32`.
  - `applyRfDemodulation` converts to gamma video voltage (`1 / 2.25`), adds subtle impedance-mismatch cable ghosts (`+0.085` at `-4` px and `-0.030` at `-8` px), and transforms to NTSC YIQ while keeping base hues intact (`OKUSAN_TINT = 0`). A horizontal bandpass (`bpDot` + `bpEdge` across `[-2..+2]`) isolates 1px white dots, fine text, and sharp vertical luminance transitions so high-frequency luma aliases into false `I/Q` cross-color along a 3.58 MHz subcarrier phase (`2*pi/3` per texel alternating per scanline), while chroma feeds back into luma as dot crawl. A mild `4.5 MHz` intercarrier ripple scales with signal brightness (`0.004 * clamp(Y, 0, 1)`).
  - Adds phase-locked horizontal scanline jitter (`0.045 * sin(...)` plus RF sync flutter), 60 Hz hum modulation, and thermal/RF snow noise.
- **Phosphor Decay**:
  - Compares `PrevTexture` / `OriginalHistory1` against the current un-interlaced sample and adds falling-edge persistence biased toward P22 green/cyan phosphors (`vec3(0.055, 0.11, 0.075)`).
- **Glass Scatter Halation**:
  - Samples 4 axial neighbors `(±2.6, 0)` and `(0, ±1.65)` in squared linear intensity, scaled by `0.044 + 0.036 * loadExcess` so flash scenes also lift internal glass scatter.

### 6. Viewport-Scaled Slot Mask & Output
- `applyPhosphorMask` computes a physical pixel pitch clamped to `[3.0, 6.0]` screen pixels based on `viewWidth / (srcWidth * 0.72)`, staggering R/G/B phosphor slots on alternating mask rows with subtle vertical row gaps.
- Mask contrast fades smoothly between `360px` and `750px` viewport widths to keep small windows legible.
- Final light undergoes corner vignetting, `1 / 2.2` display gamma encoding, bezel clipping, and subtle top-left glass reflection.
