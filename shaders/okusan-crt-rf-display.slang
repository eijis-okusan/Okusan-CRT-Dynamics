#version 450

// Okusan CRT Dynamics - Pass 1: Loose VHF RF Consumer CRT Display
// Models weak/loose antenna reception (fine-grain RF snow static, subtle sync
// flutter, faded weak-signal contrast, cable ghosts, and 3.58 MHz cross-color
// on fine detail) on top of the 480i/HV-bloom CRT pipeline.

#pragma parameter OKUSAN_RF_SNOW "RF Snow Static Strength" 1.0 0.0 2.0 0.1
#pragma parameter OKUSAN_RF_SIGNAL "RF Washout, Ghosts & Cross-Color" 1.0 0.0 2.0 0.1
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

const float SRC_GAMMA = 2.25;
const float DISPLAY_INV_GAMMA = 1.0 / 2.2;
const float BEAM_LOAD_KNEE = 0.14;
const float HV_SAG_EXPANSION = 0.015;
const float NTSC_VISIBLE_LINES = 480.0;
const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);
const vec3 GUN_CONVERGENCE = vec3(-0.13, 0.0, 0.16);
const vec3 P22_DECAY = vec3(0.055, 0.11, 0.075);

float hash11(float n)
{
    return fract(sin(n * 127.1 + 311.7) * 43758.5453123);
}

float hash21(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec3 sampleVideoPixel(sampler2D src, vec2 texelCoord, vec2 imgSz)
{
    vec2 clamped = clamp(texelCoord, vec2(0.0), imgSz - 1.0);
    vec2 uv = (clamped + 0.5) / imgSz;
    return max(texture(src, uv).rgb, vec3(0.0));
}

vec3 sampleLinearPixel(sampler2D src, vec2 texelCoord, vec2 imgSz)
{
    return pow(max(sampleVideoPixel(src, texelCoord, imgSz), vec3(1e-6)), vec3(SRC_GAMMA));
}

// Horizontal beam aperture; widens slightly under RF signal degradation.
vec3 sampleHorizontalBeam(vec2 p, float row, float rfSignal, vec2 imgSz)
{
    float center = floor(p.x + 0.5);
    float width = mix(0.55, 0.90, clamp(rfSignal, 0.0, 1.0));
    vec3 energy = vec3(0.0);
    vec3 total = vec3(0.0);
    for (int i = -2; i <= 2; ++i) {
        float x = center + float(i);
        vec3 dist = vec3(p.x - x) + GUN_CONVERGENCE;
        vec3 weight = exp(-dist * dist / (2.0 * width * width));
        energy += sampleLinearPixel(Original, vec2(x, row), imgSz) * weight;
        total += weight;
    }
    return energy / total;
}

float roundedBezelDistance(vec2 p)
{
    vec2 d = abs(p) - vec2(0.924, 0.906);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.074;
}

vec3 synthesizeScanlines(vec3 rowA, vec3 rowB, float fracY, vec2 signal, float fieldParity, float loadExcess, float pixelRowsPerSrc)
{
    vec3 picture = mix(rowA, rowB, fracY);
    if (params.OKUSAN_INTERLACED > 0.5) {
        float tvLine = (signal.y * 0.5 + 0.5) * NTSC_VISIBLE_LINES - 0.5;
        float dist = abs(mod(tvLine - fieldParity + 1.0, 2.0) - 1.0);
        float prevDist = 1.0 - dist;
        float peakLum = max(picture.r, max(picture.g, picture.b));
        float beamWidth = 0.48 + 0.12 * sqrt(peakLum) + 0.03 * loadExcess;
        float d1 = dist / beamWidth;
        float d2 = prevDist / beamWidth;
        float currentLight = exp(-0.5 * d1 * d1);
        float residualLight = exp(-0.5 * d2 * d2);
        float fieldLight = 0.34 + 0.66 * (currentLight + 0.55 * residualLight);
        float fieldPixels = 2.0 / max(abs(dFdy(tvLine)), 0.001);
        return picture * mix(0.86, fieldLight, smoothstep(1.8, 4.0, fieldPixels));
    }

    float wa = mix(0.24, 0.42, sqrt(max(rowA.r, max(rowA.g, rowA.b))));
    float wb = mix(0.24, 0.42, sqrt(max(rowB.r, max(rowB.g, rowB.b))));
    vec3 scan = rowA * exp(-0.5 * fracY * fracY / (wa * wa));
    scan += rowB * exp(-0.5 * (1.0 - fracY) * (1.0 - fracY) / (wb * wb));
    return mix(picture * 0.83, scan, smoothstep(1.35, 3.1, pixelRowsPerSrc));
}

vec3 rgbToYiq(vec3 c)
{
    return vec3(
        dot(c, LUMA_WEIGHTS),
        dot(c, vec3(0.596, -0.274, -0.322)),
        dot(c, vec3(0.211, -0.523,  0.312))
    );
}

vec3 yiqToRgb(vec3 yiq)
{
    return vec3(
        yiq.x + 0.956 * yiq.y + 0.621 * yiq.z,
        yiq.x - 0.272 * yiq.y - 0.647 * yiq.z,
        yiq.x - 1.106 * yiq.y + 1.703 * yiq.z
    );
}

// Weak-signal RF modulation: cable echo ghosts, faded weak-reception chroma/contrast,
// 3.58 MHz cross-color on fine white detail, and chroma-to-luma dot crawl.
vec3 applyRfSignalConditioning(vec3 rgb, vec2 p, vec2 q, float rfSig, float frameSeed, vec2 imgSz)
{
    if (rfSig <= 0.001) return rgb;

    vec3 vid = pow(max(rgb, vec3(1e-6)), vec3(1.0 / SRC_GAMMA));
    vec3 ghostNear = sampleVideoPixel(Original, q + vec2(-5.0, 0.0), imgSz);
    vec3 ghostFar = sampleVideoPixel(Original, q + vec2(-10.0, 0.0), imgSz);
    vid = max(vec3(0.0), vid + (0.13 * ghostNear - 0.045 * ghostFar) * rfSig);

    float lumC  = dot(sampleVideoPixel(Original, q,                  imgSz), LUMA_WEIGHTS);
    float lumL1 = dot(sampleVideoPixel(Original, q + vec2(-1.0, 0.0), imgSz), LUMA_WEIGHTS);
    float lumR1 = dot(sampleVideoPixel(Original, q + vec2( 1.0, 0.0), imgSz), LUMA_WEIGHTS);
    float lumL2 = dot(sampleVideoPixel(Original, q + vec2(-2.0, 0.0), imgSz), LUMA_WEIGHTS);
    float lumR2 = dot(sampleVideoPixel(Original, q + vec2( 2.0, 0.0), imgSz), LUMA_WEIGHTS);

    float bpDot  = lumC - 0.5 * (lumL1 + lumR1);
    float bpEdge = 0.5 * (lumR1 - lumL1) + 0.25 * (lumL2 - lumR2);
    float hfLuma = bpDot * 0.90 + bpEdge * 0.55;

    float subPhase = p.x * 2.094395 + floor(p.y) * 3.141593 + mod(frameSeed, 2.0) * 0.45;
    float subCos = cos(subPhase);
    float subSin = sin(subPhase);

    vec3 yiq = rgbToYiq(vid);
    // Faint weak-RF fade/black lift while preserving accurate base hues.
    float wash = clamp(rfSig * 0.5, 0.0, 0.85);
    yiq.yz *= mix(1.0, 0.78, wash);
    yiq.x = mix(yiq.x, yiq.x * 0.88 + 0.055, wash * 0.75);

    yiq.y += hfLuma * subCos * 0.62 * rfSig;
    yiq.z += hfLuma * subSin * 0.62 * rfSig;
    yiq.x += dot(yiq.yz, vec2(subCos, subSin)) * 0.11 * rfSig;

    vec3 outVid = clamp(yiqToRgb(yiq), vec3(1e-6), vec3(1.08));
    return pow(outVid, vec3(SRC_GAMMA));
}

// Synthesize fine-grain loose-antenna snow static (salt-and-pepper speckle)
// without elongated horizontal streaks.
float sampleRfSnowStatic(vec2 p, vec2 screen, float rfSnow, float frameSeed)
{
    if (rfSnow <= 0.001) return 0.0;

    float tSeed = mod(frameSeed, 256.0);
    // Fine grain near ~1.5-2x source dot resolution plus per-pixel snow sparkle.
    vec2 cellFine = floor(p * 1.65);
    vec2 cellGrain = floor(screen * 0.45);
    float n1 = hash21(cellFine + vec2(tSeed * 17.0, tSeed * 31.0));
    float n2 = hash21(cellGrain + vec2(tSeed * 43.0, tSeed * 11.0));
    float snow = (n1 * 0.60 + n2 * 0.40) - 0.5;

    // Fine white / black salt-and-pepper snow specks scattered across the screen.
    float speckGate = step(0.925 - 0.045 * min(rfSnow, 1.5), n1 * 0.72 + n2 * 0.28);
    float speckSign = step(0.30, hash21(cellFine * 1.3 + vec2(tSeed * 7.0, tSeed * 53.0))) * 2.0 - 1.0;

    // Black-level RF gray lift from weak antenna reception + fine snow static.
    float staticBase = 0.042 * clamp(rfSnow, 0.0, 1.5);
    return staticBase + (snow * 0.23 + speckGate * speckSign * 0.34) * rfSnow;
}

vec3 applyGlassHalation(vec3 rgb, vec2 p, float loadExcess, vec2 imgSz)
{
    vec3 halo = vec3(0.0);
    for (int i = 0; i < 4; ++i) {
        vec2 d = i < 2 ? vec2(2.6, 0.0) : vec2(0.0, 1.65);
        if (mod(float(i), 2.0) == 0.0) d = -d;
        vec3 neighbor = sampleLinearPixel(Original, floor(p + d + 0.5), imgSz);
        halo += neighbor * neighbor;
    }
    return rgb * 1.16 + halo * (0.044 + 0.036 * loadExcess);
}

vec3 applyPhosphorMask(vec3 rgb, vec2 screen, float viewWidth, float srcWidth)
{
    float pitch = clamp(viewWidth / max(srcWidth * 1.35, 1.0), 3.0, 6.0);
    float maskRow = floor(screen.y / pitch);
    float stripe = fract(screen.x / pitch + 0.5 * mod(maskRow, 2.0));
    vec3 slots = 1.0 - smoothstep(vec3(0.06), vec3(0.235),
                     abs(fract(stripe - vec3(0.0, 0.3333, 0.6667) + 0.5) - 0.5));
    float rowGap = smoothstep(0.27, 0.47, abs(fract(screen.y / pitch) - 0.5));
    float strength = mix(0.56, 1.0, smoothstep(360.0, 750.0, viewWidth)) * params.OKUSAN_MASK_STRENGTH;
    return rgb * mix(vec3(1.0), (0.72 + 0.45 * slots) * (1.0 - 0.15 * rowGap), clamp(strength, 0.0, 1.0));
}

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
    float lineHash = hash11(floor(p.y) + mod(frameSeed, 256.0) * 19.37);
    p.x += (lineHash - 0.5) * 0.32 * params.OKUSAN_RF_SNOW
         + 0.04 * sin(p.y * 1.2 + phase * 5.0) * params.OKUSAN_RF_SIGNAL;

    float y = floor(p.y);
    float fracY = fract(p.y);

    vec3 rowA = sampleHorizontalBeam(p, y, params.OKUSAN_RF_SIGNAL, imgSz);
    vec3 rowB = sampleHorizontalBeam(p, y + 1.0, params.OKUSAN_RF_SIGNAL, imgSz);
    vec3 picture = mix(rowA, rowB, fracY);
    float pixelRowsPerSrc = 1.0 / max(abs(dFdy(p.y)), 0.001);
    vec3 rgb = synthesizeScanlines(rowA, rowB, fracY, signal, fieldParity, loadExcess, pixelRowsPerSrc);

    vec2 q = floor(p + 0.5);
    rgb = applyRfSignalConditioning(rgb, p, q, params.OKUSAN_RF_SIGNAL, frameSeed, imgSz);

    vec3 previous = sampleLinearPixel(OriginalHistory1, q, imgSz);
    rgb += max(previous - picture, 0.0) * P22_DECAY;

    rgb = applyGlassHalation(rgb, p, loadExcess, imgSz);
    float viewWidth = params.OutputSize.x > 1.0 ? params.OutputSize.x : params.FinalViewportSize.x;
    rgb = applyPhosphorMask(rgb, gl_FragCoord.xy, viewWidth, imgSz.x);

    float vignette = 1.0 - 0.24 * smoothstep(0.25, 1.85, dot(face, face));
    float agcWave = 1.0 + 0.014 * params.OKUSAN_RF_SIGNAL * sin(p.y * 0.05 + phase * 3.1);
    vec3 light = pow(max(rgb * vignette * agcWave, vec3(1e-6)), vec3(DISPLAY_INV_GAMMA));

    float rfStatic = sampleRfSnowStatic(p, gl_FragCoord.xy, params.OKUSAN_RF_SNOW, frameSeed);
    light = clamp(light + rfStatic, 0.0, 1.0);

    float reflection = exp(-4.0 * dot(face - vec2(-0.42, -0.53), face - vec2(-0.42, -0.53)));
    vec3 color = max(light, vec3(0.0)) * aperture * raster + glass * (0.74 + 0.48 * reflection + lip);
    FragColor = vec4(color, 1.0);
}
