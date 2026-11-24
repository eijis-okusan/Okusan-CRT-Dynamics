// Physical CRT Automatic Beam Limiter (ABL), soft highlight limiter,
// Rec.709 -> Rec.2020 color space conversion, and ST.2084 PQ (HDR10) encoding
// for Okusan CRT Dynamics HDR Slang shaders.
// Expects `shaders/include/okusan-crt-common.inc` to be included first.

const float kOkusanMaxNits2084 = 10000.0;

// Column-major matrices matching RetroArch `hdr10.h` (`vec3 * mat3` multiplies rows).
const mat3 kOkusan709To2020 = mat3(
    0.6274040, 0.3292820, 0.0433136,
    0.0690970, 0.9195400, 0.0113612,
    0.0163916, 0.0880132, 0.8955950
);

const mat3 kOkusanExpanded709To2020 = mat3(
     0.6274040,  0.3292820, 0.0433136,
     0.0457456,  0.9417770, 0.0124772,
    -0.00121055, 0.0176041, 0.9836070
);

vec3 okusanSrgbToLinear(vec3 c)
{
    vec3 low = c / 12.92;
    vec3 high = pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4));
    vec3 isLow = step(c, vec3(0.04045));
    return mix(high, low, isLow);
}

vec3 okusanHdrSoftLimit(vec3 c, float headroom)
{
    float knee = headroom * 0.82;
    vec3 over = max(c - knee, vec3(0.0));
    float span = max(headroom - knee, 0.05);
    return min(c, vec3(knee)) + span * (over / (over + span));
}

float okusanLinearToST2084Channel(float channel)
{
    float m1 = pow(max(channel, 0.0), 0.1593017578);
    return pow((0.8359375 + 18.8515625 * m1) / (1.0 + 18.6875 * m1), 78.84375);
}

vec3 okusanLinearToST2084(vec3 colour)
{
    return vec3(
        okusanLinearToST2084Channel(colour.r),
        okusanLinearToST2084Channel(colour.g),
        okusanLinearToST2084Channel(colour.b)
    );
}

float okusanComputeHdrFactor(float paperWhiteNits, float maxNits, float hdrBoost)
{
    float safePaper = max(paperWhiteNits, 1.0);
    float headroom = clamp(maxNits / safePaper, 1.0, 4.0);
    return min(headroom - 1.0, 2.2) * clamp(hdrBoost, 0.0, 1.5);
}

// Converts scene linear CRT light into ST.2084 PQ Rec.2020 normalized to 10,000 nits.
// Preserves dark/shadow SDR accuracy while letting bright beams peak under ABL physics.
vec3 okusanFinalizeHdr10(vec3 linearLight,
                         float beamLoad,
                         float aperture,
                         float raster,
                         vec3 glassSrgb,
                         float reflection,
                         float lip,
                         float dithering,
                         float paperWhiteNits,
                         float maxNits,
                         float hdrBoost,
                         float expandGamut)
{
    float safePaper = clamp(paperWhiteNits, 40.0, 1000.0);
    float headroom = clamp(maxNits / safePaper, 1.0, 4.0);
    float hdrFactor = min(headroom - 1.0, 2.2) * clamp(hdrBoost, 0.0, 1.5);

    vec3 sdrSrgb = pow(max(linearLight, vec3(1e-6)), vec3(DISPLAY_INV_GAMMA)) + dithering;
    vec3 baseLin = okusanSrgbToLinear(max(sdrSrgb, vec3(0.0)));

    vec3 crtLin = baseLin;
    if (hdrFactor > 0.01) {
        // Automatic Beam Limiter (ABL): dark/mid scenes keep high peak drive; bright flashes sag.
        float ablGain = mix(1.0 + 0.92 * hdrFactor, 1.0 + 0.16 * hdrFactor, smoothstep(0.03, 0.48, beamLoad));
        float lum = max(dot(baseLin, LUMA_WEIGHTS), 1e-6);
        float peakDrive = mix(1.0, ablGain, smoothstep(0.05, 0.60, lum));
        crtLin = okusanHdrSoftLimit(baseLin * peakDrive, headroom);
    }

    vec3 glassLin = okusanSrgbToLinear(glassSrgb * (0.74 + 0.48 * reflection + lip));
    vec3 outRec709 = max(crtLin, vec3(0.0)) * aperture * raster + glassLin;
    vec3 outRec2020 = (expandGamut > 0.5)
        ? (outRec709 * kOkusanExpanded709To2020)
        : (outRec709 * kOkusan709To2020);
    vec3 normalizedNits = max(outRec2020, vec3(0.0)) * (safePaper / kOkusanMaxNits2084);
    return okusanLinearToST2084(normalizedNits);
}

vec3 okusanEncodeGlassHdr10(vec3 glassSrgb, float scale, float paperWhiteNits, float expandGamut)
{
    vec3 glassLin = okusanSrgbToLinear(glassSrgb * scale);
    vec3 outRec2020 = (expandGamut > 0.5)
        ? (glassLin * kOkusanExpanded709To2020)
        : (glassLin * kOkusan709To2020);
    vec3 normalizedNits = max(outRec2020, vec3(0.0)) * (clamp(paperWhiteNits, 40.0, 1000.0) / kOkusanMaxNits2084);
    return okusanLinearToST2084(normalizedNits);
}
