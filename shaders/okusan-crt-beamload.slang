#version 450

// Okusan CRT Dynamics - Pass 0: Beam Load Estimator
// Estimates screen-wide quadratic luminance across the current and previous
// source frames to model flyback high-voltage sag under bright flashes.

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

layout(set = 0, binding = 2) uniform sampler2D Original;
layout(set = 0, binding = 3) uniform sampler2D OriginalHistory1;

// Convert sRGB pixel to approximate linear luminance squared (beam current proxy).
float sampleBeamCurrent(sampler2D tex, vec2 uvNorm)
{
    vec2 uvClamped = clamp(uvNorm, vec2(0.005), vec2(0.995));
    vec3 rgb = pow(max(texture(tex, uvClamped).rgb, vec3(0.0)), vec3(2.25));
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
            curSum += sampleBeamCurrent(Original, sampleUV);
            prevSum += sampleBeamCurrent(OriginalHistory1, sampleUV);
        }
    }
    float loadNow = curSum / 64.0;
    float loadPrev = prevSum / 64.0;
    float dampedLoad = mix(loadPrev, loadNow, 0.58);
    FragColor = vec4(dampedLoad, loadNow, 0.0, 1.0);
}
