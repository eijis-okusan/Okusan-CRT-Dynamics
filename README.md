# Okusan CRT Dynamics

English | [日本語](docs/README.ja.md) | [Technical Notes](docs/ARCHITECTURE.md)

A two-pass CRT display shader pack for RetroArch focused on **beam current dynamics**: flyback high-voltage sag under bright frames, 525-line NTSC 480i field alternation over 240p sources, subtle RGB gun convergence, P22-style phosphor persistence, and glass halation — plus a dedicated loose-antenna RF television preset.

Both **Slang** (`.slangp` / `.slang`) and **GLSL** (`.glslp` / `.glsl`) pipelines are included in the same folder.

![Okusan CRT Dynamics preview in RetroArch](docs/preview.jpg)

## Features

- **Flyback HV Regulation Sag**: Pass 0 samples an 8×8 grid across the current and previous frames and smooths their squared luminance (`0.58` blend). When screen load exceeds `0.14` during bright scenes or flashes, the raster subtly expands outward and glass halation increases.
- **525-Line 480i Field Interlacing**: Alternates even and odd television fields (`FrameCount % 2`) with luminance-modulated beam width and attenuated alternate-field line illumination (`0.55`), or toggles cleanly to 240p progressive scanlines.
- **Clean RGB Beam Convergence**: Tight horizontal electron beam (`sigma = 0.55` texels) with subtle R/G/B gun convergence offsets (`-0.13`, `0.0`, `+0.16` texels).
- **P22 Decay, Halation & Slot Mask**: Short green/cyan-biased persistence compared against the previous frame (`PrevTexture` / `OriginalHistory1`), 4-tap axial glass scatter, rounded bezel silhouette, and viewport-scaled staggered RGB phosphor slots.
- **Loose-Antenna Consumer RF (`okusan-crt-rf`)**: Optional second display pass adding weak-reception black lift and chroma washout, fine-grain salt-and-pepper snow static, gentle sync flutter, cable reflection ghosts, and 3.58 MHz cross-color on fine white detail — all independently tunable.

## Presets

| Preset | Format | Target Drivers | Profile |
| --- | --- | --- | --- |
| `okusan-crt-rgb.slangp` | Slang | Metal, Vulkan, D3D11/12 | Clean 525-line 480i / HV-bloom RGB CRT |
| `okusan-crt-rf.slangp` | Slang | Metal, Vulkan, D3D11/12 | Loose VHF RF TV with fine snow, washout, ghosts & cross-color |
| `okusan-crt-rgb.glslp` | GLSL | OpenGL (`gl` / `glcore`) | Clean 525-line 480i / HV-bloom RGB CRT |
| `okusan-crt-rf.glslp` | GLSL | OpenGL (`gl` / `glcore`) | Loose VHF RF TV with fine snow, washout, ghosts & cross-color |

## Installation (RetroArch)

1. Copy the `Okusan-CRT-Dynamics` folder into your RetroArch shader directory (check **Settings → Directory → Video Shader**, under `shaders_slang/` or `shaders_glsl/`, or directly under `shaders/`).
2. Launch a game and open the **Quick Menu** (`F1` / `fn + F1` on macOS).
3. Go to **Shaders → Video Shaders → ON**.
4. Choose **Load Preset** → `Okusan-CRT-Dynamics` → **`okusan-crt-rgb`** (clean RGB) or **`okusan-crt-rf`** (loose RF television).
5. *(Optional)* Go to **Shaders → Save → Save Global Preset** to keep it active automatically.

## Shader Parameters

| Parameter | Preset | Default | Range | Effect |
| --- | --- | --- | --- | --- |
| `OKUSAN_INTERLACED` | Both | `1.0` | `0.0 - 1.0` | `1.0` = 525-line 480i fields, `0.0` = 240p scanlines |
| `OKUSAN_HV_BLOOM` | Both | `1.0` | `0.0 - 2.0` | Flyback high-voltage sag raster expansion & halation boost |
| `OKUSAN_CURVATURE` | Both | `1.0` | `0.0 - 1.5` | Tube barrel warp & curved bezel curvature |
| `OKUSAN_MASK_STRENGTH` | Both | `1.0` | `0.0 - 1.5` | Staggered RGB phosphor slot mask strength |
| `OKUSAN_RF_SNOW` | RF | `1.0` | `0.0 - 2.0` | Fine-grain snow static, black lift & subtle sync flutter |
| `OKUSAN_RF_SIGNAL` | RF | `1.0` | `0.0 - 2.0` | Weak-RF washout, cable ghosts & 3.58 MHz white-dot cross-color |

## Pipeline Overview

```
OrigTexture (N) + PrevTexture (N-1)
   │
   ▼  Pass 0: shaders/okusan-crt-beamload.{glsl,slang}  (32x32 float)
      Samples an 8x8 grid per frame, squares luma, blends 58% current / 42% previous
   │
   ▼  Pass 1: shaders/okusan-crt-{display,rf-display}.{glsl,slang}   (viewport)
      Bezel SDF + HV bloom warp ─► [NTSC RF mod/noise/demod] ─► 480i/240p scanlines ─►
      P22 decay ─► Halation ─► Slot mask ─► Vignette & glass glint
```

For full mathematical and implementation details, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Compatibility Notes

- Handles power-of-two padded source textures cleanly in GLSL (`OrigInputSize` / `OrigTextureSize` and `InputSize` / `TextureSize`).
- Adapts phosphor slot pitch across HiDPI/Retina displays and standard 1x windows without oversized RGB blocks.
- **First-load shader cache**: On the very first load of the preset (especially Slang on Metal/Vulkan), RetroArch compiles the shaders into the driver cache, which can briefly cause audio crackling or a short stutter. Once cached on subsequent launches, playback runs cleanly; raising **Settings → Audio → Output → Audio Latency (ms)** (e.g. `96`–`128`) also helps prevent audio underruns.

## License

Released under the [MIT License](LICENSE).
