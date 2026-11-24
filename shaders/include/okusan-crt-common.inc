// Shared 525-line CRT geometry, horizontal electron-beam convergence,
// scanline synthesis, glass halation, and viewport-scaled phosphor slot mask
// for Okusan CRT Dynamics Slang shaders.

const float SRC_GAMMA = 2.25;
const float DISPLAY_INV_GAMMA = 1.0 / 2.2;
const float BEAM_SIGMA_X = 0.55;
const float BEAM_LOAD_KNEE = 0.14;
const float HV_SAG_EXPANSION = 0.015;
const float NTSC_VISIBLE_LINES = 480.0; // 525 total NTSC lines minus 45 vertical blanking lines
const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);
const vec3 GUN_CONVERGENCE = vec3(-0.13, 0.0, 0.16);
const vec3 P22_DECAY = vec3(0.055, 0.11, 0.075);

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

// 5-tap horizontal RGB beam aperture with slight analog gun convergence offset.
vec3 sampleHorizontalBeam(sampler2D origTex, vec2 p, float row, vec2 imgSz)
{
    float center = floor(p.x + 0.5);
    vec3 energy = vec3(0.0);
    vec3 total = vec3(0.0);
    for (int i = -2; i <= 2; ++i) {
        float x = center + float(i);
        vec3 dist = vec3(p.x - x) + GUN_CONVERGENCE;
        vec3 weight = exp(-dist * dist / (2.0 * BEAM_SIGMA_X * BEAM_SIGMA_X));
        energy += sampleLinearPixel(origTex, vec2(x, row), imgSz) * weight;
        total += weight;
    }
    return energy / total;
}

// Signed distance to the rounded bezel aperture in curved face space [-1, 1].
float roundedBezelDistance(vec2 p)
{
    vec2 d = abs(p) - vec2(0.924, 0.906);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.074;
}

// Render either 525-line 480i alternating fields or progressive 240p scanlines.
vec3 synthesizeScanlines(vec3 rowA,
                         vec3 rowB,
                         float fracY,
                         vec2 signal,
                         float fieldParity,
                         float loadExcess,
                         float pixelRowsPerSrc,
                         float interlacedFlag)
{
    vec3 picture = mix(rowA, rowB, fracY);
    if (interlacedFlag > 0.5) {
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

// 4-tap axial glass halation weighted by squared neighbor intensity and HV load.
vec3 applyGlassHalation(sampler2D origTex, vec3 rgb, vec2 p, float loadExcess, vec2 imgSz)
{
    vec3 halo = vec3(0.0);
    for (int i = 0; i < 4; ++i) {
        vec2 d = i < 2 ? vec2(2.6, 0.0) : vec2(0.0, 1.65);
        if (mod(float(i), 2.0) == 0.0) d = -d;
        vec3 neighbor = sampleLinearPixel(origTex, floor(p + d + 0.5), imgSz);
        halo += neighbor * neighbor;
    }
    return rgb * 1.16 + halo * (0.044 + 0.036 * loadExcess);
}

// Staggered RGB phosphor slot mask scaled to preserve fine pitch across HiDPI and 1x viewports.
// When hdrFactor > 0, deepens dark mask valleys slightly while boosting phosphor centers so HDR
// output compensates for slot-mask light loss without dulling the image.
vec3 applyPhosphorMask(vec3 rgb,
                       vec2 screen,
                       float viewWidth,
                       float srcWidth,
                       float maskStrength,
                       float hdrFactor)
{
    float pitch = clamp(viewWidth / max(srcWidth * 1.35, 1.0), 3.0, 6.0);
    float maskRow = floor(screen.y / pitch);
    float stripe = fract(screen.x / pitch + 0.5 * mod(maskRow, 2.0));
    vec3 slots = 1.0 - smoothstep(vec3(0.06), vec3(0.235),
                     abs(fract(stripe - vec3(0.0, 0.3333, 0.6667) + 0.5) - 0.5));
    float rowGap = smoothstep(0.27, 0.47, abs(fract(screen.y / pitch) - 0.5));
    float strength = mix(0.56, 1.0, smoothstep(360.0, 750.0, viewWidth)) * maskStrength;

    float floorLift = mix(0.72, 0.54, clamp(hdrFactor * 0.45, 0.0, 1.0));
    float peakSpan = mix(0.45, 0.72, clamp(hdrFactor * 0.45, 0.0, 1.0));
    return rgb * mix(vec3(1.0), (floorLift + peakSpan * slots) * (1.0 - 0.15 * rowGap), clamp(strength, 0.0, 1.0));
}
