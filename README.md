# Okusan CRT Dynamics

English | [日本語](docs/README.ja.md) | [Technical Notes](docs/ARCHITECTURE.md)

A two-pass RGB CRT display shader for RetroArch focused on **beam current dynamics**: flyback high-voltage sag under bright flashes, 525-line NTSC 480i field alternation over 240p sources, subtle RGB gun convergence, P22-style phosphor persistence, and glass halation.

Both **Slang** (`.slangp` / `.slang`) and **GLSL** (`.glslp` / `.glsl`) pipelines are included in the same folder.

## Features

- **Flyback HV Regulation Sag**: Whole-screen bright flashes pull down anode voltage briefly, producing a subtle outward raster bloom and lifted glass halation across two frames.
- **525-Line 480i Field Interlacing**: Alternates even and odd television fields (`FrameCount % 2`) with luminance-modulated beam width and residual field persistence, or toggles cleanly to 240p progressive scanlines.
- **Clean RGB Beam Convergence**: Tight horizontal electron beam (`sigma = 0.55` texels) with subtle R/G/B gun convergence offsets (`-0.13`, `0.0`, `+0.16` texels).
- **P22 Decay, Halation & Slot Mask**: Short green/cyan-biased persistence on falling edges, 4-tap axial glass scatter, rounded bezel silhouette, and viewport-scaled staggered RGB phosphor slots.

## Presets

| Preset | Format | Target Drivers | Profile |
| --- | --- | --- | --- |
| `okusan-crt-rgb.slangp` | Slang | Metal, Vulkan, D3D11/12 | 525-line 480i / HV-bloom RGB CRT |
| `okusan-crt-rgb.glslp` | GLSL | OpenGL (`gl` / `glcore`) | 525-line 480i / HV-bloom RGB CRT |

## Installation (RetroArch)

1. Copy the `Okusan-CRT-Dynamics` folder into your RetroArch shader directory (check **Settings → Directory → Video Shader**, under `shaders_slang/` or `shaders_glsl/`, or directly under `shaders/`).
2. Launch a game and open the **Quick Menu** (`F1` / `fn + F1` on macOS).
3. Go to **Shaders → Video Shaders → ON**.
4. Choose **Load Preset** → `Okusan-CRT-Dynamics` → **`okusan-crt-rgb`**.
5. *(Optional)* Go to **Shaders → Save → Save Global Preset** to keep it active automatically.

## Shader Parameters

| Parameter | Default | Range | Effect |
| --- | --- | --- | --- |
| `OKUSAN_INTERLACED` | `1.0` | `0.0 - 1.0` | `1.0` = 525-line 480i fields, `0.0` = 240p scanlines |
| `OKUSAN_HV_BLOOM` | `1.0` | `0.0 - 2.0` | Flyback high-voltage sag raster expansion & halation boost |
| `OKUSAN_CURVATURE` | `1.0` | `0.0 - 1.5` | Tube barrel warp & curved bezel curvature |
| `OKUSAN_MASK_STRENGTH` | `1.0` | `0.0 - 1.5` | Staggered RGB phosphor slot mask strength |

## Pipeline Overview

```
OrigTexture (N) + PrevTexture (N-1)
   │
   ▼  Pass 0: shaders/okusan-crt-beamload.{glsl,slang}  (32x32 float)
      Samples an 8x8 grid per frame, squares luma, blends 58% current / 42% previous
   │
   ▼  Pass 1: shaders/okusan-crt-display.{glsl,slang}   (viewport)
      Bezel SDF + HV bloom warp ─► 5-tap RGB beam ─► 480i/240p scanlines ─►
      P22 decay ─► Halation ─► Slot mask ─► Vignette & glass glint
```

For full mathematical and implementation details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Compatibility Notes

- Handles power-of-two padded source textures cleanly in GLSL (`OrigInputSize` / `OrigTextureSize` and `InputSize` / `TextureSize`).
- Adapts phosphor slot pitch across HiDPI/Retina displays and standard 1x windows without oversized RGB blocks.

## License

Released under the [MIT License](LICENSE).
