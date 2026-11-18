# Okusan CRT Dynamics

English | [日本語](docs/README.ja.md) | [Technical Notes](docs/ARCHITECTURE.md)

A two-pass consumer CRT television shader for RetroArch, built around **beam current dynamics**: high-voltage flyback sag under screen-wide flashes, 525-line NTSC 480i field alternation over 240p sources, P22-style phosphor persistence, and subtle composite chroma smear.

Both **Slang** (`.slangp` / `.slang`) and **GLSL** (`.glslp` / `.glsl`) pipelines are included in the same folder.

## Why "CRT Dynamics"?

Many CRT shaders focus strictly on static scanlines and shadow masks. Real consumer sets react continuously to the video signal driving the tube:

- **Flyback HV Regulation Sag**: Bright full-screen flashes (thunderstorms, explosions, white fades) pull down the anode voltage slightly, causing a subtle outward raster bloom and stronger glass halation that decays over two frames.
- **525-Line 480i Field Interlacing**: Alternates even and odd television fields (`FrameCount % 2`) with beam-width modulation by luminance and residual field decay, or switches cleanly to classic 240p progressive scanlines.
- **RGB vs. Consumer Composite**: Compare a sharp RGB aperture with gun convergence offset (`okusan-crt-rgb`) against NTSC composite chroma bandwidth smear, line crawl, and 60 Hz hum (`okusan-crt-composite`).
- **Organic P22 Persistence & Slot Mask**: Slight green/cyan-biased frame decay on falling brightness, four-tap glass scatter halation, rounded bezel silhouette, and viewport-scaled staggered RGB phosphor slots.

## Presets

| Preset | Format | Target Drivers | Profile |
| --- | --- | --- | --- |
| `okusan-crt-rgb.slangp` | Slang | Metal, Vulkan, D3D11/12 | Crisp RGB consumer CRT |
| `okusan-crt-composite.slangp` | Slang | Metal, Vulkan, D3D11/12 | NTSC composite video CRT |
| `okusan-crt-rgb.glslp` | GLSL | OpenGL (`gl` / `glcore`) | Crisp RGB consumer CRT |
| `okusan-crt-composite.glslp` | GLSL | OpenGL (`gl` / `glcore`) | NTSC composite video CRT |

## Installation (RetroArch)

1. Download or clone this repository into your RetroArch shader directory:
   - Check **Settings → Directory → Video Shader** inside RetroArch to see the active path.
   - Place `Okusan-CRT-Dynamics` under `shaders_slang/` (Metal/Vulkan/D3D) or `shaders_glsl/` (OpenGL), or directly under `shaders/`.
2. Launch any game, open the **Quick Menu** (`F1` / `fn + F1` on macOS).
3. Go to **Shaders → Video Shaders → ON**.
4. Choose **Load Preset** → `Okusan-CRT-Dynamics` → pick `okusan-crt-rgb` or `okusan-crt-composite`.
5. *(Optional)* Go to **Shaders → Save → Save Global Preset** (or per-core / per-game preset) to keep it enabled automatically.

> Note: RetroArch only lists `.slangp` presets when using Metal/Vulkan/D3D drivers, and `.glslp` presets when using OpenGL (`gl` / `glcore`).

## Shader Parameters

| Parameter | RGB / Composite Default | Range | Effect |
| --- | --- | --- | --- |
| `OKUSAN_COMPOSITE` | `0.0` / `1.0` | `0.0 - 1.0` | Composite chroma smear, horizontal shimmer, and hum |
| `OKUSAN_INTERLACED` | `1.0` | `0.0 - 1.0` | `1.0` = 525-line 480i fields, `0.0` = 240p scanlines |
| `OKUSAN_HV_BLOOM` | `1.0` | `0.0 - 2.0` | Flyback high-voltage sag raster expansion & halation boost |
| `OKUSAN_CURVATURE` | `1.0` | `0.0 - 1.5` | Tube barrel warp & curved face geometry |
| `OKUSAN_MASK_STRENGTH` | `1.0` | `0.0 - 1.5` | Staggered RGB phosphor slot mask strength |

## Pipeline Overview

```
OrigTexture (N) + PrevTexture (N-1)
   │
   ▼  Pass 0: shaders/okusan-crt-beamload.{glsl,slang}  (32x32 float)
      Samples an 8x8 grid per frame, squares luma, blends 58% current / 42% previous
   │
   ▼  Pass 1: shaders/okusan-crt-display.{glsl,slang}   (viewport)
      Bezel SDF + HV bloom warp ─► 5-tap beam ─► 480i/240p scanlines ─►
      Composite bleed ─► P22 decay ─► Halation ─► Slot mask ─► Vignette & glass glint
```

For full mathematical and implementation details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Compatibility Notes

- Supports power-of-two padded input textures (`OrigInputSize` / `OrigTextureSize`) cleanly in GLSL as well as native normalized coordinates in Slang.
- Designed primarily for 240p/224p arcade and 8/16-bit console content scaled to 720p–4K displays; `OKUSAN_MASK_STRENGTH` scales smoothly on lower-resolution windows to avoid moiré.

## License

Released under the [MIT License](LICENSE).
