#version 450

// Okusan CRT Dynamics - Pass 1: 525-Line Interlaced RGB CRT Display (HDR10)
// Emits Rec.2020 ST.2084 PQ directly (requires Video -> HDR ON in RetroArch),
// applying physical flyback ABL, slot-mask brightness compensation, and soft highlight limiting.

#pragma format A2B10G10R10_UNORM_PACK32

#pragma parameter OKUSAN_INTERLACED "NTSC 480i Field Interlace (0=240p, 1=480i)" 1.0 0.0 1.0 1.0
#pragma parameter OKUSAN_HV_BLOOM "Flyback HV Bloom Strength" 1.0 0.0 2.0 0.1
#pragma parameter OKUSAN_CURVATURE "Tube Curvature" 1.0 0.0 1.5 0.1
#pragma parameter OKUSAN_MASK_STRENGTH "Phosphor Slot Mask" 1.0 0.0 1.5 0.1
#pragma parameter OKUSAN_HDR_PAPER_WHITE "HDR Paper White Luminance (nits)" 250.0 80.0 600.0 10.0
#pragma parameter OKUSAN_HDR_MAX_NITS "HDR Peak Display Luminance (nits)" 800.0 200.0 4000.0 50.0
#pragma parameter OKUSAN_HDR_BOOST "HDR CRT Peak Boost & ABL" 1.0 0.0 1.5 0.1
#pragma parameter OKUSAN_HDR_EXPAND_GAMUT "HDR Gamut (0=Rec709 Phosphor, 1=Expanded)" 0.0 0.0 1.0 1.0

layout(push_constant) uniform Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    vec4 FinalViewportSize;
    uint FrameCount;
    float OKUSAN_INTERLACED;
    float OKUSAN_HV_BLOOM;
    float OKUSAN_CURVATURE;
    float OKUSAN_MASK_STRENGTH;
    float OKUSAN_HDR_PAPER_WHITE;
    float OKUSAN_HDR_MAX_NITS;
    float OKUSAN_HDR_BOOST;
    float OKUSAN_HDR_EXPAND_GAMUT;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;

layout(set = 0, binding = 2) uniform sampler2D Source;           // Pass 0 output: damped quadratic beam load
layout(set = 0, binding = 3) uniform sampler2D Original;         // Current source frame
layout(set = 0, binding = 4) uniform sampler2D OriginalHistory1; // Previous source frame for phosphor persistence

#include "include/okusan-crt-common.inc"
#include "include/okusan-hdr10.inc"

void main()
{
    vec2 imgSz = max(params.OriginalSize.xy, vec2(1.0));
    float beamLoad = texture(Source, vec2(0.5, 0.5)).r;
    float loadExcess = max(beamLoad - BEAM_LOAD_KNEE, 0.0) * params.OKUSAN_HV_BLOOM;
    float phase = mod(float(params.FrameCount), 4096.0) / 59.94;
    float fieldParity = mod(float(params.FrameCount), 2.0);

    vec2 face = vTexCoord * 2.0 - 1.0;
    vec2 warp = vec2(0.083, 0.110) * params.OKUSAN_CURVATURE;
    vec2 curved = face * (vec2(1.0 + 0.015 * params.OKUSAN_CURVATURE) + face.yx * face.yx * warp);
    float edgeDistance = roundedBezelDistance(curved);
    vec3 glass = vec3(0.010, 0.014, 0.017);
    if (edgeDistance > 0.07) {
        vec3 outerPq = okusanEncodeGlassHdr10(glass, 0.50, params.OKUSAN_HDR_PAPER_WHITE, params.OKUSAN_HDR_EXPAND_GAMUT);
        FragColor = vec4(outerPq, 1.0);
        return;
    }

    float aperture = 1.0 - smoothstep(-0.012, 0.005, edgeDistance);
    float lip = exp(-abs(edgeDistance - 0.023) * 75.0);

    float hvBloom = 1.0 + HV_SAG_EXPANSION * loadExcess;
    vec2 signal = curved / (vec2(0.94, 0.90) * hvBloom);
    vec2 signalEdge = abs(signal);
    float raster = (1.0 - smoothstep(1.0, 1.0 + 2.0 / imgSz.x, signalEdge.x))
                 * (1.0 - smoothstep(1.0, 1.0 + 2.0 / imgSz.y, signalEdge.y));

    vec2 p = (signal * 0.5 + 0.5) * imgSz - 0.5;
    float y = floor(p.y);
    float fracY = fract(p.y);

    vec3 rowA = sampleHorizontalBeam(Original, p, y, imgSz);
    vec3 rowB = sampleHorizontalBeam(Original, p, y + 1.0, imgSz);
    vec3 picture = mix(rowA, rowB, fracY);
    float pixelRowsPerSrc = 1.0 / max(abs(dFdy(p.y)), 0.001);
    vec3 rgb = synthesizeScanlines(rowA, rowB, fracY, signal, fieldParity, loadExcess,
                                   pixelRowsPerSrc, params.OKUSAN_INTERLACED);

    vec2 q = floor(p + 0.5);
    vec3 previous = sampleLinearPixel(OriginalHistory1, q, imgSz);
    rgb += max(previous - picture, 0.0) * P22_DECAY;

    rgb = applyGlassHalation(Original, rgb, p, loadExcess, imgSz);
    float hdrFactor = okusanComputeHdrFactor(params.OKUSAN_HDR_PAPER_WHITE, params.OKUSAN_HDR_MAX_NITS, params.OKUSAN_HDR_BOOST);
    float viewWidth = params.OutputSize.x > 1.0 ? params.OutputSize.x : params.FinalViewportSize.x;
    rgb = applyPhosphorMask(rgb, gl_FragCoord.xy, viewWidth, imgSz.x, params.OKUSAN_MASK_STRENGTH, hdrFactor);

    float vignette = 1.0 - 0.24 * smoothstep(0.25, 1.85, dot(face, face));
    float hum = 1.0 + 0.003 * sin(p.y * 0.08 + phase * 2.0);
    float noise = fract(sin(dot(mod(gl_FragCoord.xy, 317.0), vec2(12.9898, 78.233)) + phase * 17.0) * 43758.5453) - 0.5;
    float reflection = exp(-4.0 * dot(face - vec2(-0.42, -0.53), face - vec2(-0.42, -0.53)));

    vec3 hdr10 = okusanFinalizeHdr10(rgb * vignette * hum,
                                     beamLoad,
                                     aperture,
                                     raster,
                                     glass,
                                     reflection,
                                     lip,
                                     noise * 0.008,
                                     params.OKUSAN_HDR_PAPER_WHITE,
                                     params.OKUSAN_HDR_MAX_NITS,
                                     params.OKUSAN_HDR_BOOST,
                                     params.OKUSAN_HDR_EXPAND_GAMUT);
    FragColor = vec4(hdr10, 1.0);
}
