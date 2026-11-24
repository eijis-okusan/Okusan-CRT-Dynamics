// Shared NTSC VHF RF modulation, coaxial echo ghosts, IF waveform noise,
// and 6-tap orthogonal subcarrier demodulation for Okusan CRT Dynamics Slang shaders.
// Expects `shaders/include/okusan-crt-common.inc` to be included first.

const float PI = 3.14159265;
const float SUBCARRIER_RAD_PER_TEXEL = 2.09439510; // 2 * pi / 3 per source pixel (~3.58 MHz)
const float RF_GHOST_NEAR_TAP = -5.0;
const float RF_GHOST_FAR_TAP = -10.0;
const float RF_GHOST_NEAR_GAIN = 0.12;
const float RF_GHOST_FAR_GAIN = 0.04;
const float RF_CHROMA_NOISE_PASSBAND = 0.45;
const float RF_SYNC_FLUTTER = 0.30;

// Sin-free integer-independent hashes so GPU fast-math cannot introduce periodic banding.
float hash13(vec3 p3)
{
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

float hash11(float n)
{
    return hash13(vec3(n, n * 0.37, 17.13));
}

// Continuous 1D band-limited analog noise along a single scanline (uncorrelated across lines).
float sample1DBandNoise(float x, float row, float seed)
{
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    float a = hash13(vec3(i,       row, seed));
    float b = hash13(vec3(i + 1.0, row, seed));
    return mix(a, b, u) - 0.5;
}

// Emulate RF receiver IF thermal Gaussian noise + impulse static along scanline x.
float sampleRfWaveformNoise(float x, float row, float rfSnow, float frameSeed)
{
    if (rfSnow <= 0.001) return 0.0;

    float s = mod(frameSeed, 1024.0);
    float g1 = sample1DBandNoise(x * 0.85, row, s * 1.13 + 3.7);
    float g2 = sample1DBandNoise(x * 1.35 + 17.3, row, s * 2.41 + 19.1);
    float g3 = sample1DBandNoise(x * 1.95 + 53.1, row, s * 3.79 + 41.9);
    float gauss = (g1 * 0.50 + g2 * 0.35 + g3 * 0.25);

    float impRnd = hash13(vec3(floor(x * 0.90), row, s * 5.17 + 7.3));
    float impMask = smoothstep(0.89 - 0.04 * min(rfSnow, 1.5), 0.995, impRnd);
    float impSign = hash13(vec3(floor(x * 0.90), row, s * 7.03 + 29.0)) > 0.28 ? 1.0 : -1.0;

    return (gauss * 0.36 + impMask * impSign * 0.52) * rfSnow;
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

// Emulate NTSC RF transmission & TV demodulation across one scanline.
vec3 sampleRfScanline(sampler2D origTex, vec2 p, float row, float rfSnow, float rfSig, float frameSeed, vec2 imgSz)
{
    float subcarrierLinePhase = row * PI + mod(frameSeed, 2.0) * 0.45;
    float wash = clamp(rfSig * 0.5, 0.0, 0.85);
    float baseLift = 0.040 * clamp(rfSnow, 0.0, 1.5);

    float yAcc = 0.0;
    float iAcc = 0.0;
    float qAcc = 0.0;

    for (int k = 0; k < 6; ++k) {
        float offset = (float(k) - 2.5) * 0.5;
        float xPos = p.x + offset;

        float x0 = floor(xPos);
        float fx = xPos - x0;
        vec3 s0 = sampleVideoPixel(origTex, vec2(x0, row), imgSz);
        vec3 s1 = sampleVideoPixel(origTex, vec2(x0 + 1.0, row), imgSz);
        vec3 vid = mix(s0, s1, fx);

        if (rfSig > 0.001) {
            vec3 g1 = sampleVideoPixel(origTex, vec2(floor(xPos + RF_GHOST_NEAR_TAP + 0.5), row), imgSz);
            vec3 g2 = sampleVideoPixel(origTex, vec2(floor(xPos + RF_GHOST_FAR_TAP + 0.5), row), imgSz);
            vid = max(vec3(0.0), vid + (RF_GHOST_NEAR_GAIN * g1 - RF_GHOST_FAR_GAIN * g2) * rfSig);
        }

        vec3 yiq = rgbToYiq(vid);
        yiq.yz *= mix(1.0, 0.82, wash);
        yiq.x = mix(yiq.x, yiq.x * 0.88 + 0.035, wash * 0.75);

        float scPhase = xPos * SUBCARRIER_RAD_PER_TEXEL + subcarrierLinePhase;
        float scCos = cos(scPhase);
        float scSin = sin(scPhase);
        float chromaDrive = mix(0.0, 1.0, clamp(rfSig, 0.0, 1.5));
        float rfCarrier = yiq.x + baseLift + chromaDrive * (yiq.y * scCos + yiq.z * scSin);

        float rfNoise = sampleRfWaveformNoise(xPos, row, rfSnow, frameSeed);
        rfNoise *= (rfNoise < 0.0) ? mix(1.0, 0.55, clamp(yiq.x, 0.0, 1.0)) : 1.0;

        yAcc += (rfCarrier + rfNoise) * (1.0 / 6.0);
        float rxChroma = rfCarrier + rfNoise * RF_CHROMA_NOISE_PASSBAND;
        iAcc += rxChroma * scCos * (2.0 / 6.0);
        qAcc += rxChroma * scSin * (2.0 / 6.0);
    }

    vec3 outYiq;
    if (rfSig <= 0.001) {
        vec3 cleanYiq = rgbToYiq(sampleVideoPixel(origTex, vec2(floor(p.x + 0.5), row), imgSz));
        outYiq = vec3(yAcc, cleanYiq.y + iAcc * 0.35, cleanYiq.z + qAcc * 0.35);
    } else {
        outYiq = vec3(yAcc, iAcc * 0.85, qAcc * 0.85);
    }

    vec3 outVid = clamp(yiqToRgb(outYiq), vec3(1e-6), vec3(1.08));
    vec3 lin = pow(outVid, vec3(SRC_GAMMA));

    vec3 convShift = GUN_CONVERGENCE * 0.5;
    vec3 linL = sampleLinearPixel(origTex, vec2(floor(p.x - 1.0 + 0.5), row), imgSz);
    vec3 linR = sampleLinearPixel(origTex, vec2(floor(p.x + 1.0 + 0.5), row), imgSz);
    return mix(lin, vec3(linR.r, lin.g, linL.b) * 0.14 + lin * 0.86, abs(convShift.b));
}
