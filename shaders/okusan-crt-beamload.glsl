#version 120

// Okusan CRT Dynamics - Pass 0: Beam Load Estimator
// Estimates screen-wide quadratic luminance across the current and previous
// source frames to model flyback high-voltage sag under bright flashes.

#if defined(VERTEX)

uniform mat4 MVPMatrix;
attribute vec4 VertexCoord;
attribute vec2 TexCoord;
varying vec2 vTexCoord;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    vTexCoord = TexCoord;
}

#elif defined(FRAGMENT)

uniform sampler2D OrigTexture;
uniform sampler2D PrevTexture;
uniform vec2 OrigInputSize;
uniform vec2 OrigTextureSize;
uniform vec2 PrevInputSize;
uniform vec2 PrevTextureSize;
varying vec2 vTexCoord;

// Convert sRGB pixel to approximate linear luminance squared (beam current proxy).
float sampleBeamCurrent(sampler2D tex, vec2 uvNorm, vec2 inputSz, vec2 texSz)
{
    vec2 activeScale = inputSz / max(texSz, vec2(1.0));
    vec2 uvClamped = clamp(uvNorm, vec2(0.005), vec2(0.995)) * activeScale;
    vec3 rgb = pow(max(texture2D(tex, uvClamped).rgb, vec3(0.0)), vec3(2.25));
    float luma = dot(rgb, vec3(0.299, 0.587, 0.114));
    return luma * luma;
}

void main()
{
    // Uniform 8x8 spatial grid per frame; blends current and previous frames
    // to approximate flyback HV filter capacitor response.
    float curSum = 0.0;
    float prevSum = 0.0;
    for (int iy = 0; iy < 8; ++iy) {
        float fy = (float(iy) + 0.5) / 8.0;
        for (int ix = 0; ix < 8; ++ix) {
            float fx = (float(ix) + 0.5) / 8.0;
            vec2 sampleUV = vec2(fx, fy);
            curSum += sampleBeamCurrent(OrigTexture, sampleUV, OrigInputSize, OrigTextureSize);
            prevSum += sampleBeamCurrent(PrevTexture, sampleUV, PrevInputSize, PrevTextureSize);
        }
    }
    float loadNow = curSum / 64.0;
    float loadPrev = prevSum / 64.0;
    float dampedLoad = mix(loadPrev, loadNow, 0.58);
    gl_FragColor = vec4(dampedLoad, loadNow, 0.0, 1.0);
}

#endif
