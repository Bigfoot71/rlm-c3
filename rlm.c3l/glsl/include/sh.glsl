#ifndef SH_GLSL
#define SH_GLSL

// ================================
// Constants
// ================================

#define SH_MIN_ROUGHNESS 0.04
#define SH_DIELECTRIC_F0 0.04

#define SH_PI     3.1415926535897931
#define SH_INV_PI 0.3183098861837907

// ================================
// Functions: Helpers
// ================================

float _sh_pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

float _sh_alpha(float roughness)
{
    float r = max(roughness, SH_MIN_ROUGHNESS);
    return r * r;
}

float _sh_saturate(float x)
{
    return clamp(x, 0.0, 1.0);
}

// ================================
// Functions: Base Lighting
// ================================

// Diffuse

vec3 shDiffuseLambert(vec3 albedo)
{
    return albedo * SH_INV_PI;
}

vec3 shDiffuseBurley(vec3 albedo, float roughness, float NdotV, float NdotL, float LdotH)
{
    float fd90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
    float fl = 1.0 + (fd90 - 1.0) * _sh_pow5(1.0 - NdotL);
    float fv = 1.0 + (fd90 - 1.0) * _sh_pow5(1.0 - NdotV);
    return albedo * SH_INV_PI * fl * fv;
}

// Fresnel

vec3 shF0(vec3 albedo, float metallic)
{
    return mix(vec3(SH_DIELECTRIC_F0), albedo, metallic);
}

float shFresnelSchlick(float f0, float cosTheta)
{
    return f0 + (1.0 - f0) * _sh_pow5(1.0 - _sh_saturate(cosTheta));
}

vec3 shFresnelSchlick(vec3 f0, float cosTheta)
{
    return f0 + (1.0 - f0) * _sh_pow5(1.0 - _sh_saturate(cosTheta));
}

vec3 shFresnelSchlickRoughness(vec3 f0, float roughness, float NdotV)
{
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) * _sh_pow5(1.0 - _sh_saturate(NdotV));
}

// Blinn-Phong

float shShininess(float roughness)
{
    float a = _sh_alpha(roughness);
    return max(2.0 / (a * a) - 2.0, 0.0);
}

float shSpecularBlinnPhong(float NdotH, float shininess)
{
    return (shininess + 8.0) / (8.0 * SH_PI) * pow(_sh_saturate(NdotH), shininess);
}

vec3 shBrdfBlinnPhong(vec3 n, vec3 v, vec3 l, vec3 diffuse, vec3 specular, float shininess)
{
    vec3 h = v + l;
    h *= inversesqrt(max(dot(h, h), 1e-8));
    return shDiffuseLambert(diffuse) + specular * shSpecularBlinnPhong(dot(n, h), shininess);
}

// Cook-Torrance GGX

float shD_GGX(float NdotH, float roughness)
{
    float a  = _sh_alpha(roughness);
    float a2 = a * a;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 * SH_INV_PI / (d * d);
}

float shV_SmithGGXCorrelated(float NdotV, float NdotL, float roughness)
{
    float a  = _sh_alpha(roughness);
    float a2 = a * a;
    float gv = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    float gl = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-5);
}

vec3 shSpecularGGX(vec3 f0, float roughness, float NdotV, float NdotL, float NdotH, float VdotH)
{
    float D = shD_GGX(NdotH, roughness);
    float V = shV_SmithGGXCorrelated(NdotV, NdotL, roughness);
    vec3  F = shFresnelSchlick(f0, VdotH);
    return D * V * F;
}

vec3 shBrdfGGX(vec3 n, vec3 v, vec3 l, vec3 albedo, float roughness, float metallic)
{
    vec3 h = v + l;
    h *= inversesqrt(max(dot(h, h), 1e-8));

    float NdotV = max(dot(n, v), 1e-4);
    float NdotL = _sh_saturate(dot(n, l));
    float NdotH = _sh_saturate(dot(n, h));
    float VdotH = _sh_saturate(dot(v, h));
    float LdotH = _sh_saturate(dot(l, h));

    vec3 f0 = shF0(albedo, metallic);
    vec3 F  = shFresnelSchlick(f0, VdotH);

    vec3 spec = shSpecularGGX(f0, roughness, NdotV, NdotL, NdotH, VdotH);
    vec3 diff = (1.0 - metallic) * (1.0 - F) * shDiffuseBurley(albedo, roughness, NdotV, NdotL, LdotH);

    return diff + spec;
}

// ================================
// Functions: Direct Lighting
// ================================

// Unit direction to a point light and distance to it
vec3 shDirPoint(vec3 p, vec3 lightPos, out float dist)
{
    vec3 d = lightPos - p;
    dist = length(d);
    return d / max(dist, 1e-5);
}

// Inverse-square smoothly reaching 0 at `radius`
float shAttenuationPoint(float dist, float radius)
{
    float r = dist / radius;
    float w = _sh_saturate(1.0 - r * r * r * r);
    return w * w / (dist * dist + 1.0);
}

// `spotDir` points from the light toward the scene (requires cosInner > cosOuter)
float shAttenuationSpot(vec3 l, vec3 spotDir, float cosOuter, float cosInner)
{
    float cd = dot(-l, spotDir);
    float t  = _sh_saturate((cd - cosOuter) / max(cosInner - cosOuter, 1e-4));
    return t * t;
}

// `radiance` should already include color, intensity, attenuation and shadow
vec3 shDirect(vec3 brdf, vec3 radiance, vec3 n, vec3 l)
{
    return brdf * radiance * _sh_saturate(dot(n, l));
}

// ================================
// Functions: Direct Shadows
// ================================

// Hard shadow in [0, 1]
// `ro` should be offset from the surface (p + n * bias)
// Directional light: maxt = scene size; Point light: maxt = distance to the light
#define SH_HARD_SHADOW(name, scene)                                              \
float name(vec3 ro, vec3 rd, float mint, float maxt, int iterations, float e)    \
{                                                                                \
    float t = mint;                                                              \
    for (int i = 0; i < iterations && t < maxt; i++)                             \
    {                                                                            \
        float h = scene(ro + rd * t).d;                                          \
        if (h < e) return 0.0;                                                   \
        t += h;                                                                  \
    }                                                                            \
    return 1.0;                                                                  \
}

// Soft shadow in [0, 1] (Inigo Quilez improved technique)
// `k` is hardness: low = wide penumbra, high (eg. 64) = sharp
// Directional light: maxt = scene size; Point light: maxt = distance to the light
#define SH_SOFT_SHADOW(name, scene)                                                         \
float name(vec3 ro, vec3 rd, float mint, float maxt, int iterations, float e, float k)      \
{                                                                                           \
    float res = 1.0;                                                                        \
    float ph  = 1e20;                                                                       \
    float t   = mint;                                                                       \
    for (int i = 0; i < iterations && t < maxt; i++)                                        \
    {                                                                                       \
        float h = scene(ro + rd * t).d;                                                     \
        if (h < e) return 0.0;                                                              \
        float y = h * h / (2.0 * ph);                                                       \
        float d = sqrt(max(h * h - y * y, 0.0));                                            \
        res = min(res, k * d / max(t - y, 1e-5));                                           \
        ph = h;                                                                             \
        t += h;                                                                             \
    }                                                                                       \
    return _sh_saturate(res);                                                               \
}

// ================================
// Functions: Rim Lighting
// ================================

float shRim(vec3 n, vec3 v, float power)
{
    return pow(1.0 - _sh_saturate(dot(n, v)), power);
}

// Easier to tune than a power
float shRimSmooth(vec3 n, vec3 v, float edge0, float edge1)
{
    return smoothstep(edge0, edge1, 1.0 - _sh_saturate(dot(n, v)));
}

// ================================
// Functions: Ambient
// ================================

// Blends ground and sky colors by normal
vec3 shAmbientHemisphere(vec3 n, vec3 up, vec3 skyColor, vec3 groundColor)
{
    return mix(groundColor, skyColor, 0.5 + 0.5 * dot(n, up));
}

// Analytic environment BRDF (Karis)
// Multiply it by the environment color for specular ambient
vec3 shEnvBrdfApprox(vec3 f0, float roughness, float NdotV)
{
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4( 1.0,  0.0425,  1.040, -0.040);

    vec4  r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * _sh_saturate(NdotV))) * r.x + r.y;
    vec2  ab = vec2(-1.04, 1.04) * a004 + r.zw;

    return f0 * ab.x + ab.y;
}

// ================================
// Functions: Ambient Occlusion
// ================================

// Ambient occlusion sampled along the normal (Inigo Quilez)
// Good default: samples = 5, maxDist = 0.12, decay = 0.95, strength = 3.0
#define SH_AO(name, scene)                                                              \
float name(vec3 p, vec3 n, int samples, float maxDist, float decay, float strength)     \
{                                                                                       \
    float occ = 0.0;                                                                    \
    float w   = 1.0;                                                                    \
    for (int i = 1; i <= samples; i++)                                                  \
    {                                                                                   \
        float h = maxDist * float(i) / float(samples);                                  \
        float d = scene(p + n * h).d;                                                   \
        occ += (h - d) * w;                                                             \
        w *= decay;                                                                     \
    }                                                                                   \
    return _sh_saturate(1.0 - strength * occ);                                          \
}

// Specular occlusion derived from diffuse AO (Lagarde)
float shSpecularOcclusion(float NdotV, float ao, float roughness)
{
    return _sh_saturate(pow(NdotV + ao, exp2(-16.0 * roughness - 1.0)) - 1.0 + ao);
}

// ================================
// Functions: Reflections
// ================================

// Single reflection bounce
// Calls `vec3 shade(vec3 p, vec3 n, vec3 rd, int mat)` on hit and returns `miss` otherwise
// `e` is both the hit threshold and the normal epsilon (review?)
#define SH_REFLECTION(name, scene, shade)                                                \
vec3 name(vec3 ro, vec3 rd, int iterations, float maxDist, float e, vec3 miss)           \
{                                                                                        \
    float t = 0.0;                                                                       \
    for (int i = 0; i < iterations && t < maxDist; i++)                                  \
    {                                                                                    \
        vec3 p = ro + rd * t;                                                            \
        Sd s = scene(p);                                                                 \
        if (s.d < e)                                                                     \
        {                                                                                \
            const vec2 k = vec2(1.0, -1.0);                                              \
            vec3 n = normalize(                                                          \
                k.xyy * scene(p + k.xyy * e).d +                                         \
                k.yyx * scene(p + k.yyx * e).d +                                         \
                k.yxy * scene(p + k.yxy * e).d +                                         \
                k.xxx * scene(p + k.xxx * e).d                                           \
            );                                                                           \
            return shade(p, n, rd, s.mat);                                               \
        }                                                                                \
        t += s.d;                                                                        \
    }                                                                                    \
    return miss;                                                                         \
}

// ================================
// Functions: Transmittance
// ================================

// Beer-Lambert transmittance from a per-channel absorption `sigma`
// Pair it with the thickness from SF_THICKNESS
vec3 shTransmittance(vec3 sigma, float thickness)
{
    return exp(-sigma * thickness);
}

// Beer-Lambert transmittance from the color transmitted at a thickness of 1.0
// Pair it with the thickness from SF_THICKNESS
vec3 shTransmittanceTint(vec3 tint, float thickness)
{
    return pow(max(tint, vec3(1e-4)), vec3(thickness));
}

// Fake subsurface scattering (Barre-Brisebois)
// Multiply by the thickness transmittance
// Good default: distortion = 0.2, power = 4.0
float shTranslucency(vec3 n, vec3 v, vec3 l, float distortion, float power)
{
    vec3 h = l + n * distortion;
    return pow(_sh_saturate(dot(v, -h)), power);
}

// ================================
// Functions: Fog
// ================================

float shFogExp(float dist, float density)
{
    return 1.0 - exp(-density * dist);
}

float shFogExp2(float dist, float density)
{
    float x = density * dist;
    return 1.0 - exp(-x * x);
}

// `rd` must be normalized
float shFogHeight(vec3 ro, vec3 rd, float dist, float density, float falloff)
{
    float k    = falloff * rd.y;
    float base = density * exp(-falloff * ro.y);
    float tau  = (abs(k * dist) < 1e-4) ? base * dist : base * (1.0 - exp(-k * dist)) / k;
    return 1.0 - exp(-tau);
}

// Fog color tinted toward the sun color when looking at the sun
vec3 shFogColor(vec3 fogColor, vec3 sunColor, vec3 rd, vec3 sunDir, float power)
{
    return mix(fogColor, sunColor, pow(_sh_saturate(dot(rd, sunDir)), power));
}

vec3 shFogApply(vec3 color, vec3 fogColor, float amount)
{
    return mix(color, fogColor, amount);
}

// ================================
// Functions: Glowing
// ================================

// Glow falloff from a scene distance
// Accumulate it per step (glow += shGlow(s.d, 8.0) * stepLength)
// or use the minimum distance after the march (glow = shGlow(minD, 8.0))

// Exponential glow falloff
float shGlow(float d, float falloff)
{
    return exp(-falloff * max(d, 0.0));
}

// Inverse-square glow falloff (with a longer tail)
// `radius` is the half intensity distance
float shGlowInverse(float d, float radius)
{
    float x = max(d, 0.0) / radius;
    return 1.0 / (1.0 + x * x);
}

#endif // SH_GLSL
