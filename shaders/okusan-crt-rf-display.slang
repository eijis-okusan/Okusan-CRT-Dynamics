#version 450

// Okusan CRT Dynamics - Pass 1: Loose VHF RF NTSC Signal & Noise Emulation (SDR)
// Emulates NTSC YIQ composite encoding on each scanline, cable echo ghosts,
// loose-antenna thermal Gaussian + impulse noise before demodulation, and
// 6-tap orthogonal subcarrier demodulation over the 480i CRT.

#pragma parameter OKUSAN_RF_SNOW "RF Antenna Noise & Static" 1.0 0.0 2.0 0.1
#pragma parameter OKUSAN_RF_SIGNAL "RF Echoes, Washout & Subcarrier Leaks" 1.0 0.0 2.0 0.1
#pragma parameter OKUSAN_INTERLACED "NTSC 480i Field Interlace (0=240p, 1=480i)" 1.0 0.0 1.0 1.0
#pragma parameter OKUSAN_HV_BLOOM "Flyback HV Bloom Strength" 1.0 0.0 2.0 0.1
#pragma parameter OKUSAN_CURVATURE "Tube Curvature" 1.0 0.0 1.5 0.1
#pragma parameter OKUSAN_MASK_STRENGTH "Phosphor Slot Mask" 1.0 0.0 1.5 0.1

layout(push_constant) uniform Push
{
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    vec4 FinalViewportSize;
    uint FrameCount;
    float OKUSAN_RF_SNOW;
    float OKUSAN_RF_SIGNAL;
    float OKUSAN_INTERLACED;
    float OKUSAN_HV_BLOOM;
    float OKUSAN_CURVATURE;
    float OKUSAN_MASK_STRENGTH;
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

layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D Original;
layout(set = 0, binding = 4) uniform sampler2D OriginalHistory1;

#include "include/okusan-crt-common.inc"
#include "include/okusan-crt-rf.inc"

void main()
{
    vec2 imgSz = max(params.OriginalSize.xy, vec2(1.0));
    float beamLoad = texture(Source, vec2(0.5, 0.5)).r;
    float loadExcess = max(beamLoad - BEAM_LOAD_KNEE, 0.0) * params.OKUSAN_HV_BLOOM;
    float frameSeed = mod(float(params.FrameCount), 4096.0);
    float phase = frameSeed / 59.94;
    float fieldParity = mod(float(params.FrameCount), 2.0);

    vec2 face = vTexCoord * 2.0 - 1.0;
    vec2 warp = vec2(0.083, 0.110) * params.OKUSAN_CURVATURE;
    vec2 curved = face * (vec2(1.0 + 0.015 * params.OKUSAN_CURVATURE) + face.yx * face.yx * warp);
    float edgeDistance = roundedBezelDistance(curved);
    vec3 glass = vec3(0.010, 0.014, 0.017);
    if (edgeDistance > 0.07) {
        FragColor = vec4(glass * 0.50, 1.0);
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
    float lineHash = hash11(floor(p.y) + mod(frameSeed, 1024.0) * 19.37);
    p.x += (lineHash - 0.5) * RF_SYNC_FLUTTER * params.OKUSAN_RF_SNOW
         + 0.04 * sin(p.y * 1.2 + phase * 5.0) * params.OKUSAN_RF_SIGNAL;

    float y = floor(p.y);
    float fracY = fract(p.y);

    vec3 rowA = sampleRfScanline(Original, p, y, params.OKUSAN_RF_SNOW, params.OKUSAN_RF_SIGNAL, frameSeed, imgSz);
    vec3 rowB = sampleRfScanline(Original, p, y + 1.0, params.OKUSAN_RF_SNOW, params.OKUSAN_RF_SIGNAL, frameSeed, imgSz);
    vec3 picture = mix(rowA, rowB, fracY);
    float pixelRowsPerSrc = 1.0 / max(abs(dFdy(p.y)), 0.001);
    vec3 rgb = synthesizeScanlines(rowA, rowB, fracY, signal, fieldParity, loadExcess,
                                   pixelRowsPerSrc, params.OKUSAN_INTERLACED);

    vec2 q = floor(p + 0.5);
    vec3 previous = sampleLinearPixel(OriginalHistory1, q, imgSz);
    rgb += max(previous - picture, 0.0) * P22_DECAY;

    rgb = applyGlassHalation(Original, rgb, p, loadExcess, imgSz);
    float viewWidth = params.OutputSize.x > 1.0 ? params.OutputSize.x : params.FinalViewportSize.x;
    rgb = applyPhosphorMask(rgb, gl_FragCoord.xy, viewWidth, imgSz.x, params.OKUSAN_MASK_STRENGTH, 0.0);

    float vignette = 1.0 - 0.24 * smoothstep(0.25, 1.85, dot(face, face));
    float agcWave = 1.0 + 0.014 * params.OKUSAN_RF_SIGNAL * sin(p.y * 0.05 + phase * 3.1);
    vec3 light = pow(max(rgb * vignette * agcWave, vec3(1e-6)), vec3(DISPLAY_INV_GAMMA));

    float reflection = exp(-4.0 * dot(face - vec2(-0.42, -0.53), face - vec2(-0.42, -0.53)));
    vec3 color = max(light, vec3(0.0)) * aperture * raster + glass * (0.74 + 0.48 * reflection + lip);
    FragColor = vec4(color, 1.0);
}
